extends SceneTree
# Home's scene. 0.31.114-0.31.117: the heroes on the dais, clear of each other, the medallions and PLAY; the painting
# down the whole screen; empty chest slots; the line under PLAY.
# 0.31.138 (Kevin picked the war room concept for Home -- "the camera overlooking the live map ... the castles/land in
# the background ... some heroes standing next to the map table looking at it" -- and: "Make sure to bring the scene to
# life with candles emitting light glow along with the glow effect of sun. Also maybe glimmer of the water and birds
# flying in sky ect ect"):
#  - the backdrop is the war room (bg_war_room.webp and its window/water mask), covering 20:9 and 21:9 phones;
#  - the war table and the concept's four heroes in 3D (the Mage, the Barbarian, the Knight, the Ranger) in their
#    equipped looks; no hero reaches into another; the two beyond the table stand clear of the side medallions; the
#    table fits the screen's width and its near edge is above PLAY;
#  - the live map on the table: the war's holders and battles are painted on it; Home and the war map both watch the war
#    (closing one doesn't stop the other's);
#  - alive: birds fly, every candle flickers (the 12 painted and the 6 on the table), the sun's rays turn, the water
#    shader moves; reduce motion holds it all still; a safe start draws the painting alone;
#  - (kept) each empty chest slot shows a dim chest, the line under PLAY.
#   godot --headless --path godot -s res://tests/home_heroes_test.gd
const App = preload("res://scripts/app/siege_app.gd")
const HomeScene = preload("res://scripts/app/home_scene.gd")
const WarRoom = preload("res://scripts/app/war_room.gd")
const Screens = preload("res://scripts/app/screens.gd")
const Social = preload("res://scripts/meta/social.gd")
const LandData = preload("res://scripts/app/war_land_data.gd")
const Eco = preload("res://scripts/meta/economy.gd")

var app
var phone                                # Home's scene as a 420 x 933 phone lays it out
var still                                # ... with reduce motion
var bare                                 # ... on a safe start
var fails: Array = []
var t := 0.0
var step := 0
var flick := {}

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

func _scene(calm: bool, safe: bool) -> Control:
	var box := Control.new()
	box.size = Vector2(420, 933)
	root.add_child(box)
	var s := HomeScene.new(calm, safe)
	s.size = Vector2(420, 933)
	box.add_child(s)
	return s

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")      # nothing listens there
	var base := "user://homeheroes-%d" % Time.get_ticks_usec()
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

func _play_top(h: float) -> float:
	# PLAY's top on a 420-wide phone this tall (siege_app.home_play_top, no notch)
	var hh := h - (6.0 + App.TOP_H) - float(App.ChatTicker.H) - App.TAB_H - 30.0
	return 6.0 + App.TOP_H + 4.0 + float(Screens.home_layout(hh).play)

func _box(slot: Node3D, weapons := true) -> AABB:
	# the hero's box: his body (its skinned mesh's bounds), and with weapons, the exact extent of the weapons he holds
	var box := AABB()
	var first := true
	for v in slot.find_children("*", "MeshInstance3D", true, false):
		var mi := v as MeshInstance3D
		if mi.mesh == null or mi.mesh is QuadMesh or not mi.is_visible_in_tree():
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		if mi.skin == null:
			if not weapons:
				continue
			var vfirst := true
			for si in mi.mesh.get_surface_count():
				for p in (mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
					var q: Vector3 = mi.global_transform * p
					b = AABB(q, Vector3.ZERO) if vfirst else b.expand(q)
					vfirst = false
		box = b if first else box.merge(b)
		first = false
	return box

func _on_screen(s, p: Vector3) -> Vector2:
	var r = s.room
	return r.position + r.cam.unproject_position(p) * (r.size / Vector2(r.viewport.size))

func _rect(s, box: AABB) -> Rect2:
	var rect := Rect2()
	for i in 8:
		var p := _on_screen(s, box.get_endpoint(i))
		rect = Rect2(p, Vector2.ZERO) if i == 0 else rect.expand(p)
	return rect

func _process(d: float) -> bool:
	t += d
	if step == 0:
		if t < 1.5:
			if not bool(app.profile.d.get("tutorial_done", false)):
				app.profile.d.tutorial_done = true                   # (the players-online line under PLAY, not the tutorial)
				app.rebuild()
			return false
		step = 1
		var looks := {}
		for c in Eco.CLASSES:
			looks[c] = {}
		looks["knight"] = {"r": "mw/templar_sword"}                  # (an equipped look: the line-up wears it)
		for s in [phone, still]:
			s.place(_play_top(933.0))
			s.set_looks(looks)
		bare.place(_play_top(933.0))
		t = 0.0
		return false
	if step == 1:
		if t < 1.0:
			return false
		step = 2
		_checks_scene()
		for f in phone._flames:
			flick[f.core] = (f.core as Control).scale
		flick["rays"] = phone._sun_rays.rotation
		for f in still._flames:
			flick[f.core] = (f.core as Control).scale
		t = 0.0
		return false
	if t < 0.5:
		return false
	_checks_alive()
	_checks_app()
	print("HOME_HEROES_PASS" if fails.is_empty() else "HOME_HEROES_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
	return true

func _checks_scene() -> void:
	# ---- the painting
	var art: TextureRect = phone.paint_layer.get_child(0)
	var tex := art.texture
	var mask: Texture2D = (art.material as ShaderMaterial).get_shader_parameter("mask")
	check(tex != null and tex.get_size() == Vector2(1152, 2560) and mask != null and mask.get_size() == Vector2(288, 640),
		"the war room painting (%s) and its window/water mask (%s)" % [str(tex.get_size()) if tex else "none", str(mask.get_size()) if mask else "none"])
	var short := ""
	for h in [933.0, 980.0]:                                       # 20:9 (the S21 Ultra) and 21:9
		var probe := HomeScene.new()
		probe.size = Vector2(420, h)
		probe.paint_layer = Control.new()
		probe.top_layer = Control.new()
		probe.place(_play_top(h))
		if probe.painting_bottom() < h - App.TAB_H or probe.origin.y > 0.5 or probe.origin.x > 0.5:
			short += " %.0f (painting from %s to %.0f)" % [h, str(probe.origin), probe.painting_bottom()]
		probe.paint_layer.free()
		probe.top_layer.free()
		probe.free()
	check(short == "", "at 420 wide the painting covers the screen (top and sides; to the tab bar) on 20:9 and 21:9 phones%s" % short)
	# ---- the heroes
	var room = phone.room
	var built: Dictionary = room._built
	check(built.size() == 4 and built.has("mage") and built.has("barbarian") and built.has("knight") and built.has("ranger"),
		"the concept's four round the table: %s" % str(built.keys()))
	check(str(built.knight.key) == str({"r": "mw/templar_sword"}), "the heroes wear what's equipped (the Knight's look: %s)" % str(built.knight.key))
	var boxes := {}
	for c in built:
		boxes[c] = _box(built[c].node)
	var hits := []
	var names: Array = boxes.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			if (boxes[names[i]] as AABB).grow(0.03).intersects(boxes[names[j]]):
				hits.append("%s/%s" % [names[i], names[j]])
	check(hits.is_empty(), "no hero (weapons included) reaches within 6 cm of another %s" % str(hits))
	var med_bottom := 6.0 + App.TOP_H + 4.0 + float(Screens.MED_Y[2]) + 80.0     # QUESTS / SOCIAL and their labels
	var why := ""
	for c in ["mage", "barbarian"]:
		var r := _rect(phone, _box(built[c].node, false))
		if (r.position.x < 76.0 or r.end.x > 344.0) and r.position.y < med_bottom:
			why += " %s %s" % [c, str(r)]
	check(why == "", "the two beyond the table stand clear of the side medallions (they end at y %.0f)%s" % [med_bottom, why])
	# ---- the table
	var o: Vector2 = WarRoom.oval(WarRoom.RIM)
	var near := _on_screen(phone, Vector3(0.0, WarRoom.TOP_Y + 0.085, o.y - 0.12))  # (the rim's top; its apron goes behind PLAY)
	var left := _on_screen(phone, Vector3(-o.x, WarRoom.TOP_Y, 0.0))
	var right := _on_screen(phone, Vector3(o.x, WarRoom.TOP_Y, 0.0))
	var far := _on_screen(phone, Vector3(0.0, WarRoom.TOP_Y, -o.y))
	check(near.y < _play_top(933.0) and left.x >= 0.0 and right.x <= 420.0 and far.y > med_bottom - 40.0,
		"the table fits the width (%.0f..%.0f), its far edge under the medallions' rows (%.0f), its near rim over PLAY (%.0f < %.0f)" % [left.x, right.x, far.y, near.y, _play_top(933.0)])
	var foot := _on_screen(phone, Vector3.ZERO)
	var rug: Vector2 = phone.origin + Vector2(573, 1352) * phone.k
	var off: Vector2 = (foot - rug) / (Vector2(507, 256) * float(phone.k))                  # (the rug: 507 x 256 px half-axes, painted)
	check(off.length() < 0.5, "the table stands on the painted rug, well inside it (its foot %s, the rug's middle %s)" % [str(foot.round()), str(rug.round())])
	# ---- the live map
	var land = room.land
	check(land != null and land.land_mat != null and land.tiles.size() == 18 and land.disc == WarRoom.MAP_OVAL,
		"the war map's land on the table, cut to its oval")
	var terr := {"tower": {"h": "stags", "b": "b1"}, "home_lions": {"h": "lions"}}
	phone.paint_war({"terr": terr})
	var hold: PackedColorArray = land.land_mat.get_shader_parameter("holder")
	var bat: PackedFloat32Array = land.land_mat.get_shader_parameter("battle")
	var ti := LandData.IDS.find("tower")
	check(hold[ti].a > 0.5 and hold[LandData.IDS.find("mill")].a < 0.5 and bat[ti] > 0.5 and (land.tiles.tower.swords as Sprite3D).visible
		and not (land.tiles.mill.swords as Sprite3D).visible, "the war on the table: the Tower in its holder's colour, its battle pulsing, swords over it")
	# ---- a safe start
	check(bare.room == null and bare.paint_layer.get_child_count() > 2, "a safe start: the painting, no 3D")

func _checks_alive() -> void:
	var b = phone._birds
	check(b.birds.size() >= 3 and b.process_mode != Node.PROCESS_MODE_DISABLED, "birds fly in the sky (%d)" % b.birds.size())
	var painted := 0
	var table := 0
	var moved := 0
	for f in phone._flames:
		if int(f.table) < 0:
			painted += 1
		else:
			table += 1
		if (f.core as Control).scale != flick[f.core]:
			moved += 1
	check(painted == HomeScene.FLAMES.size() and table == WarRoom.CANDLE_SPOTS.size() * WarRoom.CANDLES.size() and moved == phone._flames.size(),
		"every candle flickers: %d painted, %d on the table (%d moved)" % [painted, table, moved])
	check(phone._sun_rays.rotation != float(flick.rays), "the sun's rays turn")
	var art: TextureRect = phone.paint_layer.get_child(0)
	check(float((art.material as ShaderMaterial).get_shader_parameter("motion")) == 1.0, "the water glimmers (the painting's shader moves)")
	var held := 0
	for f in still._flames:
		if (f.core as Control).scale == flick[f.core]:
			held += 1
	var sart: TextureRect = still.paint_layer.get_child(0)
	check(held == still._flames.size() and still._birds.process_mode == Node.PROCESS_MODE_DISABLED
		and float((sart.material as ShaderMaterial).get_shader_parameter("motion")) == 0.0 and still.room.calm,
		"reduce motion: the flames, the water and the candles' light hold still, no birds")
	# ---- Home and the war map both watch the war
	var s := Social.new()
	s.war_open("home")
	s.war_open("map")
	s.war_close("map")
	var both := s.war_watching
	s.war_close("home")
	check(both and not s.war_watching, "closing the war map leaves Home's table watching; closing both stops it")
	s.free()

func _checks_app() -> void:
	# ---- in the app
	check(app.home_scene != null and app.hero_node == app.home_scene.room and app.home_scene.room != null,
		"Home's backdrop is the war room, its heroes the line-up")
	check(absf(app.hero_layer.size.y - app.size.y) < 1.0, "the hero layer is as tall as the app (%.0f / %.0f)" % [app.hero_layer.size.y, app.size.y])
	app.social.war = {"terr": {"forge": {"h": "ravens"}}}
	app._on_social_changed("war")
	var hold: PackedColorArray = app.home_scene.room.land.land_mat.get_shader_parameter("holder")
	check(hold[LandData.IDS.find("forge")].a > 0.5, "the war as the server tells it shows on Home's table")
	# ---- the ribbon
	check(not has_text(app.content, "16 v 16 SIEGE") and has_text(app.content, "16 vs 16"), "no ribbon on Home; the line under PLAY says 16 vs 16")
	# ---- empty chest slots
	var ghosts: Array = app.content.find_children("*", "TextureRect", true, false).filter(func(n): return n.has_meta("empty_slot") and n.is_visible_in_tree())
	var empty_n: int = 4 - app.profile.chests().size()
	check(empty_n > 0 and ghosts.size() == empty_n and not has_text(app.content, "Win to earn\na chest") and has_text(app.content, "WIN TO EARN"),
		"each empty chest slot shows a dim chest (%d of %d), the first says WIN TO EARN" % [ghosts.size(), empty_n])
	# ---- the online line
	var os_node := Node.new()
	os_node.set_script(load("res://scripts/app/online_status.gd"))
	app.online_status = os_node
	var main: Label = app.online_refs.get("main")
	os_node.info = {"online": 0, "in_match": 0}
	app.paint_online()
	var alone := main.text
	os_node.info = {"online": 1, "in_match": 0}
	app.paint_online()
	var me_only := main.text
	os_node.info = {"online": 7, "in_match": 3}
	app.paint_online()
	check(alone == "LIVE SIEGE SERVER" and me_only == "LIVE SIEGE SERVER" and main.text == "7 PLAYERS ONLINE",
		"the line under PLAY: no count until someone else is on (%s / %s / %s)" % [alone, me_only, main.text])
