extends SceneTree
# Fatebound trailer 10, the vertical gameplay trailer (Kevin: "Now make a gameplay trailer that shows the actual game off
# from a players perspective. Make the trailer vertical. Make it voiced by herald and make very funny. Show how the game
# flow goes and also show some other things like guilds, heros, how battles go ect. Do not put captions so players can
# focus on watching gameplay instead of reading").
#
# Takes of the real game as a player sees it on the phone, one a process, each recorded by Movie Maker in 9:16
# (tools/trailer8_render.sh with SCRIPT=res://tools/trailer10_shots.gd, 1080 x 1920), then cut and mixed by
# tools/trailer10_edit.py under the Royal Herald (tools/trailer10_script.md).
#  - The app's own screens: Home, the Armory, a champion's window, the clan, PLAY's hero window, a chest -- the real app
#    with a mid-game profile, never the live server (SIEGE_URL unreachable; the friends and the clan are sample data, as
#    the server's answers would have them: tools/store4_app.gd's), and the title screen and the loading screen as players
#    join (their heroes in their outfits; sample names).
#  - Offline 5v5 matches against bots on the Rift (siege_mode.gd), staged like tools/store4_match.gd's but in motion:
#    who stands where, at what level, the time on the clock -- with the HUD, the game's own camera and its fog of war.
# Whatever a player would press is pressed the way a finger does it: the HUD's own stick and buttons (siege_hud.gd
# _touch / _drag: the same path a touch takes), the app's buttons (their pressed signal); and a fingertip is drawn where
# it touches, as a phone's screen recording shows taps. The game's own sounds are in the recording (Movie Maker); the
# match music is off (the edit lays the theme under the whole trailer).
#   RUN=<run> OUT_DIR=<dir>  [SNAP=t1,t2,...: PNG stills at those seconds of the take, no Movie Maker needed]
# Prints REC_START <frame> when the take begins (the edit trims to it) and SHOT_DONE when it's over.
const App = preload("res://scripts/app/siege_app.gd")
const Screens = preload("res://scripts/app/screens.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Loading = preload("res://scripts/siege/loading_screen.gd")
const TitleScreen = preload("res://scripts/app/title_screen.gd")
const Audio = preload("res://scripts/native_audio.gd")

const APP_RUNS := ["home", "armory", "golem", "outfit", "clan", "play", "chest"]
const MATCH_RUNS := ["hook", "chair", "lane", "fight", "death", "tower", "wyrm", "king"]
const LENGTH := {"home": 5.5, "armory": 5.0, "golem": 4.5, "outfit": 5.5, "clan": 5.5, "play": 5.0, "chest": 5.0,
	"lobby": 6.0, "title": 6.5,
	"hook": 4.5, "chair": 4.0, "lane": 6.0, "fight": 6.5, "death": 6.0, "tower": 6.0, "wyrm": 7.5, "king": 8.0}
const NOW := 1795000000                  # (mid-November 2026, as the store screenshots)
const ME := "stormcaller"                # your hero all trailer long, in the outfit you'll pick for him
const MY_SKIN := "stormcaller_stormforged"

# ---------- a fingertip where the screen is touched (as a phone's "show taps") ----------
class Touches extends Control:
	var fingers := {}                    # id -> {p, down, t}
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
	func press(id: int, p: Vector2) -> void:
		fingers[id] = {"p": p, "down": true, "t": 0.0}
	func move(id: int, p: Vector2) -> void:
		if fingers.has(id):
			fingers[id].p = p
	func release(id: int) -> void:
		if fingers.has(id):
			fingers[id].down = false
			fingers[id].t = 0.0
	func _process(delta: float) -> void:
		for id in fingers.keys():
			var f: Dictionary = fingers[id]
			f.t = float(f.t) + delta
			if not bool(f.down) and float(f.t) > 0.3:
				fingers.erase(id)
		queue_redraw()
	func _draw() -> void:
		for f in fingers.values():
			var p: Vector2 = f.p
			var t: float = f.t
			if bool(f.down):
				var k := clampf(t / 0.08, 0.0, 1.0)
				draw_circle(p, 17.0 * (0.7 + 0.3 * k), Color(1, 1, 1, 0.38 * k))
				draw_arc(p, 19.5 * (0.7 + 0.3 * k), 0.0, TAU, 48, Color(0, 0, 0, 0.3 * k), 2.5, true)     # (seen on light screens too)
				draw_arc(p, 18.0 * (0.7 + 0.3 * k), 0.0, TAU, 48, Color(1, 1, 1, 0.85 * k), 2.0, true)
				if t < 0.3:                   # the press ripples out
					var r := t / 0.3
					draw_arc(p, 18.0 + 22.0 * r, 0.0, TAU, 48, Color(1, 1, 1, 0.5 * (1.0 - r)), 2.0, true)
			else:
				var a := 1.0 - t / 0.3
				draw_circle(p, 17.0 + 6.0 * (1.0 - a), Color(1, 1, 1, 0.3 * a))
				draw_arc(p, 18.0 + 8.0 * (1.0 - a), 0.0, TAU, 48, Color(1, 1, 1, 0.7 * a), 2.0, true)

var run := "home"
var out_dir := "/tmp/trailer10"
var snaps: Array = []
var frames := 0
var rec0 := -1                           # the frame the take began on
var t := 0.0                             # seconds into the take (frames / 30)
var plan: Array = []                     # [t, Callable], run in order as the take passes t
var touches: Touches
var app
var mode
var ls
var ts
var audio
var _snap_next := ""
# the match's player
var stick_on := false
var stick_o := Vector2.ZERO
var steer_to := Vector2.INF              # walk there (the stick pushed that way) until near
var steer_stop := 1.5
var auto_attack := false
var _atk_at := -9.0
var sturdy := {}

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")
	run = OS.get_environment("RUN") if OS.has_environment("RUN") else run
	out_dir = OS.get_environment("OUT_DIR") if OS.has_environment("OUT_DIR") else out_dir
	if OS.has_environment("SNAP"):
		for v in OS.get_environment("SNAP").split(","):
			snaps.append(float(v))
	DirAccess.make_dir_recursive_absolute(out_dir)
	seed(10)
	var layer := CanvasLayer.new()
	layer.layer = 120
	touches = Touches.new()
	layer.add_child(touches)
	if run in APP_RUNS:
		_make_app()
	elif run in MATCH_RUNS:
		_make_match()
	elif run == "lobby":
		audio = Audio.new()
		root.add_child(audio)
		ls = Loading.new()
		ls.audio = audio
		ls.my_hero = ME
		ls.my_skin = MY_SKIN
		ls.my_name = "[WOLF] Midblade"
		root.add_child(ls)
	elif run == "title":
		ts = TitleScreen.new(null, false)
		root.add_child(ts)
	root.add_child.call_deferred(layer)
	RenderingServer.frame_post_draw.connect(func():
		if _snap_next != "":
			root.get_texture().get_image().save_png(_snap_next)
			print("SNAP ", _snap_next)
			_snap_next = "")

# ---------- the app ----------
func _make_app() -> void:
	var base := "user://trailer10-%d" % Time.get_ticks_usec()
	app = App.new()
	app.eco_autostart = false
	app.social_autostart = false
	app.version_check = false
	app.profile_path = base + "-profile.json"
	app.legacy_path = base + "-none.json"
	app.now_override = NOW
	app.intro_auto = false
	app.daily_auto = false
	root.add_child(app)

func _seed_profile() -> void:
	var p = app.profile
	p.d.name = "Midblade"
	p.d.level = 18
	p.d.xp = 900
	p.d.gold = 12840
	p.d.gems = 640
	p.d.tutorial_done = true
	p.d.pass.xp = 12 * 2500 + 900
	p.d.stats.wins = 86
	p.d.stats.matches = 141
	for h in ["stormcaller", "dragoon", "golem", "duelist", "archmage"]:
		if not (p.d.get("heroes", []) as Array).has(h):
			(p.d.heroes as Array).append(h)
	for id in ["stormcaller_stormforged", "stormcaller_frost", "golem_geode"]:
		if not (p.d.skins as Array).has(id):
			(p.d.skins as Array).append(id)
	p.d.settings["moba_hero"] = ME
	for k in ["royal", "gold", "silver", "wooden"]:
		p.add_chest(k, {})
	p.d.chests.slots[0].start = p.now() - 999999
	p.d.chests.slots[1].start = p.now() - 3600
	p.save()

func _social(with_clan: bool) -> void:
	# friends online, a party of three, the Iron Wolves at level 8 (tools/store4_app.gd's sample)
	var s = app.social
	var me := {"pid":"3fa21c9b0d", "n":"Midblade", "tt":"", "st":"online", "ct":"WOLF", "cc":"3.5.1"}
	s.me = me.duplicate()
	s.state = "online"
	s.has_clans = true
	s.has_lfg = true
	var f := [
		{"pid":"9c41e07a2b", "n":"Ironclad", "tt":"", "st":"online", "ct":"WOLF", "cc":"3.5.1"},
		{"pid":"51ab90cc3e", "n":"Mirabel", "tt":"", "st":"online"},
		{"pid":"e7d2214f80", "n":"Thornwick", "tt":"", "st":"match", "ct":"WOLF", "cc":"3.5.1"},
		{"pid":"0b3f8a1d55", "n":"Kaelen", "tt":"", "st":"online"},
		{"pid":"77c0d1e3aa", "n":"Pyra", "tt":"", "st":"offline", "seen":NOW - 3 * 3600},
	]
	s.friends = f
	s.party = {"id":"pa1", "leader":me.pid, "members":[me, f[0], f[1]], "pending":[], "max":5}
	s.lines.global = [{"n":"Ironclad", "x":"who's up for a 5v5?", "pid":"9c41e07a2b", "ct":"WOLF", "cc":"3.5.1"}]
	if with_clan:
		var members := []
		var names := ["Midblade", "Ironclad", "Thornwick", "Brannoc", "Odessa", "Vex", "Grimwald", "Lune", "Tamsin", "Corvin",
			"Isolde", "Fenwick", "Rowan", "Sable", "Hollis", "Wren", "Orrin", "Maelis"]
		for i in names.size():
			members.append({"pid":"m%02d" % i, "n":names[i], "tt":"", "st":"online" if i < 7 else "offline",
				"role":"leader" if i == 0 else ("officer" if i < 3 else "member"), "joined":1790000000, "ct":"WOLF", "cc":"3.5.1",
				"wp":maxi(0, 420 - 23 * i), "lv":30 - i})
		members[0].pid = me.pid
		s.clan = {"id":"c1", "name":"Iron Wolves", "tag":"WOLF", "house":"", "join":"open", "min_lv":5, "n":names.size(),
			"max":30, "lead":"Midblade", "cv":2, "cr":Eco.crest_of_code("3.5.1"), "cc":"3.5.1", "lv":8, "pts":2460, "fr":"silver",
			"members":members, "role":"leader", "created":1789000000, "xp":7900, "week":"2026-W47", "ends":NOW + 3 * 86400,
			"tier":Eco.clan_tier(2460), "mine_pts":420, "asks":[{"pid":"m05", "n":"Vex", "h":"golem", "at":NOW - 1200}],
			"ask_next":0, "lfg":[{"pid":"m04", "n":"Odessa", "at":NOW - 60, "size":2, "max":5}]}
	s.changed.emit("state")
	s.changed.emit("friends")
	s.changed.emit("party")
	if with_clan:
		s.changed.emit("clan")

func _find_key(key: String) -> Control:
	for n in root.find_children("*", "Control", true, false):
		if n.has_meta("action_key") and str(n.get_meta("action_key")) == key and (n as Control).is_visible_in_tree():
			return n
	return null

func _tap_key(key: String, hold := 0.12) -> void:
	# a finger on the button's middle, lifted a moment later: the button's press
	var b := _find_key(key)
	if b == null:
		print("TRAILER10 no button ", key)
		return
	var c := b.get_global_rect().get_center()
	touches.press(9, c)
	_after(hold, func():
		touches.release(9)
		if is_instance_valid(b):
			b.pressed.emit())

func _drag_scroll(sc: ScrollContainer, by: float, dur: float, at: Vector2) -> void:
	# a thumb dragging the list up by `by` px over dur (the list follows it)
	var v0 := float(sc.scroll_vertical)
	touches.press(8, at)
	var n := int(dur * 30.0)
	for i in range(1, n + 1):
		var k := float(i) / float(n)
		var e := k * k * (3.0 - 2.0 * k)
		_after(float(i) / 30.0, func():
			sc.scroll_vertical = int(v0 + by * e)
			touches.move(8, at - Vector2(0.0, by * e * 0.55)))
	_after(dur + 0.03, func(): touches.release(8))

func _after(dt: float, f: Callable) -> void:
	plan.append([t + dt, f])

# ---------- the match ----------
func _make_match() -> void:
	audio = Audio.new()
	audio.levels.music = 0.0                 # (the edit lays the theme under it all)
	root.add_child(audio)
	var p = Profile.new("user://trailer10-m-%d.json" % Time.get_ticks_usec(), "user://none.json")
	p.load_or_create()
	if not (p.d.skins as Array).has(MY_SKIN):
		(p.d.skins as Array).append(MY_SKIN)
	if not (p.d.heroes as Array).has(ME):
		(p.d.heroes as Array).append(ME)
	p.wear_skin(ME, MY_SKIN)
	p.d.name = "Midblade"
	mode = Mode.new()
	mode.moba_hero = ME
	mode.match_seed = 2026
	mode.audio = audio
	mode.profile = p
	mode.player_name = "Midblade"
	mode.clan_tag = "WOLF"
	mode.clan_crest = "3.5.1"
	mode.hq_gfx = true
	root.add_child(mode)

func s():
	return mode.sim

func _u(id: String) -> Dictionary:
	return mode.sim.by_id[id]

func _heroes(team: int) -> Array:
	var outv := []
	for u in s().units:
		if bool(u.get("hero", false)) and int(u.team) == team:
			outv.append(u)
	return outv

func _level(u: Dictionary, lv: int) -> void:
	lv = mini(lv, int(s().moba.LEVEL_MAX))
	while int(u.level) < lv:
		s().moba.add_xp(u, s().moba.need(int(u.level)))
	u.picks = []

func _place(u: Dictionary, p: Vector2, face_to: Vector2) -> void:
	u.pos = p
	u.move = Vector2.ZERO
	u.task = {}
	u.face = s().angle_of((face_to - p).normalized())

func _tough(u: Dictionary, k := 5.0, frac := 1.0) -> void:
	u.max_hp = float(u.max_hp) * k
	u.hp = float(u.max_hp) * frac

func _park(u: Dictionary) -> void:
	u.bot = false
	u.pos = s().spawn(int(u.team)) + Vector2(randf_range(-3.0, 3.0), randf_range(-2.0, 2.0))
	u.move = Vector2.ZERO
	u.task = {}

func _red_tower(lane: int, tier: int) -> Dictionary:
	for tw in s().moba.towers:
		if int(tw.team) == 1 and int(tw.lane) == lane and int(tw.tier) == tier:
			return tw
	return {}

# the names over the heroes as in an online match (sample names and clan tags: never the server's players)
const NAMES := {"you": ["Midblade", "WOLF", "3.5.1"], "b1": ["Ironclad", "WOLF", "3.5.1"], "b2": ["Mirabel", "", ""],
	"b3": ["Thornwick", "WOLF", "3.5.1"], "b4": ["Kaelen", "", ""], "r0": ["Pyra", "EMBR", "6.2.4"], "r1": ["Grimwald", "EMBR", "6.2.4"],
	"r2": ["Vex", "", ""], "r3": ["Odessa", "EMBR", "6.2.4"], "r4": ["Brannoc", "", ""]}

func _dress(time_s: float, kills: Array, gold: float, items: Array) -> void:
	s().time = time_s
	s().kills = kills
	var me := _u("you")
	me.gold = gold
	me.items = items
	var v = mode.view
	mode.hud.player_name = str(NAMES.you[0])
	v.my_name = str(NAMES.you[0])
	v.my_tag = str(NAMES.you[1])
	v.my_crest = str(NAMES.you[2])
	for id in NAMES:
		if id == "you" or not s().by_id.has(id):
			continue
		v.player_names[id] = str(NAMES[id][0])
		mode.hud.net_names[id] = str(NAMES[id][0])
		if str(NAMES[id][1]) != "":
			v.player_tags[id] = str(NAMES[id][1])
			v.player_crests[id] = str(NAMES[id][2])

func _hud_c(id: String) -> Vector2:
	for b in mode.hud._buttons():
		if str(b.id) == id:
			return b.c
	return Vector2.INF

func _hud_canvas(p: Vector2) -> Vector2:
	return mode.hud.get_global_transform() * p

func _press(id: String, hold := 0.13) -> void:
	# a thumb on the HUD's button: its own touch (the button lights, the mode acts on it as on a player's tap)
	var c := _hud_c(id)
	if c == Vector2.INF:
		return
	var fid := 3 + ["attack", "ability", "w", "e", "ult", "dodge", "ward", "recall"].find(id)
	mode.hud._touch(fid, c, true)
	touches.press(fid, _hud_canvas(c))
	_after(hold, func():
		mode.hud._touch(fid, c, false)
		touches.release(fid))

func _stick(dir: Vector2) -> void:
	# the left thumb on the stick: pushed this way (screen terms: up is toward their castle), or let go (ZERO)
	var hud = mode.hud
	if dir == Vector2.ZERO:
		if stick_on:
			hud._touch(0, stick_o, false)
			touches.release(0)
			stick_on = false
		return
	if not stick_on:
		stick_o = Vector2(hud.size.x * 0.24, hud.size.y * 0.80)
		hud._touch(0, stick_o, true)
		touches.press(0, _hud_canvas(stick_o))
		stick_on = true
	var p: Vector2 = stick_o + dir.limit_length(1.0) * 58.0
	hud._drag(0, p)
	touches.move(0, _hud_canvas(p))

func _steer() -> void:
	if steer_to == Vector2.INF or not s().alive(_u("you")):
		return
	var d: Vector2 = steer_to - (_u("you").pos as Vector2)
	if d.length() < steer_stop:
		steer_to = Vector2.INF
		_stick(Vector2.ZERO)
		return
	_stick(d.normalized())

func _walk(to: Vector2, stop := 1.5) -> void:
	steer_to = to
	steer_stop = stop

func _auto_fire() -> void:
	# tap ATTACK every so often while there's an enemy in reach (the mode aims it at the nearest)
	if not auto_attack or t - _atk_at < 0.55 or not s().alive(_u("you")):
		return
	var me := _u("you")
	var reach := float(s().stat(me, "range")) + 1.0
	var foe: Dictionary = s().nearest_enemy(me, reach, true)
	if foe.is_empty():
		var tw: Dictionary = s().moba.tower_in_range(1, me.pos, 1.0)
		var king_near: bool = s().moba.king_open(1) and (me.pos as Vector2).distance_to(s().moba.king_pos(1)) < reach + 2.5
		if tw.is_empty() and not king_near:
			return
	_atk_at = t
	_press("attack", 0.1)

func _keep_sturdy() -> void:
	for id in sturdy:
		var u := _u(id)
		if s().alive(u) and float(u.hp) < float(u.max_hp) * float(sturdy[id]):
			u.hp = float(u.max_hp) * float(sturdy[id])

func _quiet() -> void:
	mode.hud._toast = ""

# ---------- the loop ----------
func _process(delta: float) -> bool:
	frames += 1
	if rec0 < 0:
		if not _ready_to_roll():
			return false
		rec0 = frames
		print("REC_START ", frames)
		call("_take_" + run)
		if mode != null:
			for dt in [0.0, 0.1, 0.3, 0.6]:
				_after(dt, _quiet)
		return false
	t = float(frames - rec0) / 30.0
	var due := plan.filter(func(p): return float(p[0]) <= t)
	plan = plan.filter(func(p): return float(p[0]) > t)
	for p in due:
		(p[1] as Callable).call()
	if mode != null and mode.sim != null and OS.get_environment("TRACE") == "1" and (frames - rec0) % 15 == 0:
		var bits := []
		for u in _heroes(0) + _heroes(1):
			if (u.pos as Vector2).distance_to(_u("you").pos) < 16.0:
				bits.append("%s %d/%d%s" % [u.id, int(u.hp), int(u.max_hp), "" if s().alive(u) else " DOWN"])
		print("TRACE t=%.1f fb=%s kills=%s king1=%d  %s" % [t, str(s().moba.first_blood), str(s().kills),
			int((s().moba.kings[1] as Dictionary).get("hp", 0)), ", ".join(bits)])
	if mode != null and mode.sim != null:
		_steer()
		_auto_fire()
		_keep_sturdy()
	for sn in snaps:
		if absf(t - float(sn)) < 0.5 / 30.0:
			_snap_next = "%s/%s_%05.2f.png" % [out_dir, run, float(sn)]
	if t >= float(LENGTH.get(run, 5.0)) + 0.2 or (not snaps.is_empty() and t > float(snaps.max()) + 0.2):
		print("SHOT_DONE ", run)
		quit(0)
	return false

var _settle := 0
func _ready_to_roll() -> bool:
	# the take starts once what it shows is built and has settled
	if app != null:
		if frames == 3:
			_seed_profile()
			app.server_five = 0                       # (PLAY: a match against bots here, never the server's)
			app.rebuild()
		if frames == 8:
			_social(run in ["home", "clan", "play"])
			app.rebuild()
		if frames == 12 and has_method("_set_" + run):
			call("_set_" + run)
		return frames >= 60
	if mode != null:
		if mode.sim == null or not mode._build_queue.is_empty() or not mode.warmed():
			return false
		if _settle == 0:
			_settle = frames
			mode.set_render_scale(1.0)
			call("_stage_" + run)
		return frames >= _settle + 24
	if ls != null:
		return frames >= 20
	if ts != null:
		return frames >= 2
	return true

# ---------- app takes ----------
func _set_home() -> void:
	app.show_tab("home")

func _take_home() -> void:
	pass                                          # Home: the champions round the fire, PLAY, the chests; held

func _set_armory() -> void:
	app.show_tab("home")

func _take_armory() -> void:
	# the ARMORY tab tapped -> the heroes, the list dragged down past the roles
	_after(0.25, func(): _tap_key("tab_locker"))
	_after(0.55, func():
		app.locker_tab = "heroes"
		app.rebuild())
	_after(1.7, func(): _drag_scroll(app.content_scroll, 640.0, 1.6, Vector2(300.0, 600.0)))

func _set_golem() -> void:
	app.open_champion("golem", "golem_geode", true)

func _take_golem() -> void:
	pass                                          # the Golem's window: in 3D on his stage, his effects, his outfits

func _set_outfit() -> void:
	app.profile.wear_skin(ME, "")
	app.open_champion(ME, "", true)

func _take_outfit() -> void:
	# his outfits, each tapped in turn: his own look -> Frostbound -> Stormforged
	_after(0.9, func(): _tap_key("champ_skin_stormcaller_frost"))
	_after(2.5, func(): _tap_key("champ_skin_stormcaller_stormforged"))

func _set_clan() -> void:
	app.show_tab("home")

func _take_clan() -> void:
	_after(0.3, func(): _tap_key("tab_alliance"))
	_after(0.45, func():
		if not (app.modal != null and str(app.modal.get_script().resource_path).ends_with("clan_panel.gd")):
			app.open_clan())
	_after(2.6, func(): _tap_key("clan_open_members"))        # its members: eighteen of them, seven on

func _set_play() -> void:
	app.profile.wear_skin(ME, MY_SKIN)
	app.show_tab("home")

func _take_play() -> void:
	# PLAY -> the hero window (your Stormcaller picked) -> BATTLE -> the match's loading card
	_after(0.5, func(): _tap_key("play"))
	_after(2.3, func(): _tap_key("moba_battle"))

func _set_chest() -> void:
	app.show_tab("home")

func _take_chest() -> void:
	# a chest ready to open on Home: OPEN -> it bursts -> what's inside
	_after(0.4, func(): _tap_key("chest_open_0"))
	_after(1.3, func(): _tap_key("chest_modal_open"))
	_after(1.75, func():
		if app.modal != null and app.modal.get("result") is Dictionary:
			app.modal.result["shard"] = "dragoon")      # (before the rewards rise: a hero shard, as the store shot)

# ---------- the lobby: players joining (sample names), then PREPARING THE BATTLEFIELD ----------
func _lobby_msg(n: int, left: float) -> Dictionary:
	var names := ["Midblade", "Ironclad", "Mirabel", "Thornwick", "Kaelen", "Pyra", "Grimwald", "Vex", "Odessa", "Brannoc"]
	var hr := [ME, "knight", "druid", "golem", "musketeer", "barbarian", "necromancer", "duelist", "archmage", "dragoon"]
	var sk := [MY_SKIN, "knight_lion", "druid_blossom", "golem_geode", "", "barbarian_mammoth", "", "", "", ""]
	var ct := ["WOLF", "WOLF", "", "WOLF", "", "EMBR", "EMBR", "", "EMBR", ""]
	return {"t":"lobby", "left":left, "wait":20.0, "names":names.slice(0, n), "tt":names.slice(0, n).map(func(_x): return ""),
		"ct":ct.slice(0, n), "hr":hr.slice(0, n), "sk":sk.slice(0, n), "me":0, "online":n, "slots":10, "running":false}

func _take_lobby() -> void:
	ls.update(_lobby_msg(1, 9.0))
	_after(0.6, func(): ls.update(_lobby_msg(2, 8.4)))
	_after(1.1, func(): ls.update(_lobby_msg(3, 7.9)))
	_after(1.5, func(): ls.update(_lobby_msg(5, 7.5)))
	_after(2.3, func(): ls.update(_lobby_msg(7, 6.7)))
	_after(3.0, func(): ls.update(_lobby_msg(10, 6.0)))
	_after(4.6, func(): ls.loading())

# ---------- the title (the app's opening: the title slams onto the wall, TAP TO START) ----------
func _take_title() -> void:
	ts.home_ready()

# ---------- match takes ----------
func _common(time_s: float, kills: Array, gold: float, items: Array, lv: int) -> void:
	_dress(time_s, kills, gold, items)
	var sm = s().moba
	sm.wave_at = INF                              # (no waves but the take's own)
	sm.first_blood = time_s > 120.0               # (mid-match: the first kill was long ago)
	for u in _heroes(0) + _heroes(1):
		_level(u, lv)
		u.max_hp = float(s().stat(u, "hp"))
		u.hp = u.max_hp
		_park(u)
	_quiet()

func _stage_hook() -> void:
	# a teamfight in the river, everyone level 9 (tools/store4_match.gd's): your storm finishes two -- DOUBLE KILL
	_common(540.0, [14, 11], 1285.0, ["archon", "greaves", "titan"], 9)
	var blue := _heroes(0)
	var red := _heroes(1)
	var bp := [Vector2(-5.2, 3.8), Vector2(-1.9, 3.1), Vector2(2.3, 3.3), Vector2(5.6, 4.0)]
	var rp := [Vector2(-5.0, -1.2), Vector2(-1.6, -2.2), Vector2(1.8, -1.4), Vector2(5.2, -2.0), Vector2(0.2, -5.2)]
	var j := 0
	hook_pairs = []
	for i in blue.size():
		var u: Dictionary = blue[i]
		_tough(u, 6.0, 0.5 + 0.12 * float(i % 4))
		if str(u.id) != "you":
			_place(u, bp[j], rp[j])
			hook_pairs.append([str(u.id), rp[j]])
			j += 1
	for i in red.size():
		var u: Dictionary = red[i]
		_tough(u, 6.0, 0.4 + 0.12 * float(i % 4))
		_place(u, rp[i], bp[mini(i, 3)])
		hook_pairs.append([str(u.id), bp[mini(i, 3)]])
		if i == 1 or i == 2:
			u.hp = 1.0                                # (your storm finishes these two: a DOUBLE KILL)
	_place(_u("you"), Vector2(0.3, 7.4), Vector2(0.0, -2.0))
	_u("you").kills = 9
	sturdy["you"] = 0.6

var hook_pairs: Array = []

func _hook_cast(id: String, at_p: Vector2, what: String) -> void:
	var u := _u(id)
	if not s().alive(u):
		return
	u.face = s().angle_of((at_p - (u.pos as Vector2)).normalized())
	match what:
		"q": s().act(id, "ability")
		"a": s().act(id, "attack")
		_: s().act(id, "spell", what)

func _take_hook() -> void:
	# everyone swinging or casting at the one across, a beat apart; you: STATIC FIELD, then the storm
	var acts := ["q", "a", "w", "e", "a", "q", "w", "a", "e"]
	for i in hook_pairs.size():
		var pr: Array = hook_pairs[i]
		_after(0.1 + 0.12 * float(i), func(): _hook_cast(str(pr[0]), pr[1], acts[i % acts.size()]))
		_after(1.4 + 0.15 * float(i % 4), func(): _hook_cast(str(pr[0]), pr[1], "a"))
	_stick(Vector2(0.0, -0.6))
	_after(0.3, func(): _stick(Vector2.ZERO))
	_after(0.4, func(): _press("w"))
	_after(0.95, func(): _press("ult"))
	_after(2.4, func():
		for u in _heroes(0) + _heroes(1):
			if str(u.id) != "you":
				u.bot = true)
	_after(2.6, func(): _press("ability"))
	_after(3.0, func(): auto_attack = true)

func _stage_chair() -> void:
	# the first seconds of a match, in our keep: you step out toward our King on his throne
	_common(3.0, [0, 0], 500.0, [], 1)
	var me := _u("you")
	_place(me, s().spawn(0), s().moba.king_pos(0))
	var blue := _heroes(0)
	var k := 0
	for u in blue:
		if str(u.id) == "you":
			continue
		_place(u, s().spawn(0) + Vector2(-4.0 + 2.6 * float(k), 1.5), s().moba.king_pos(0))
		u.bot = true
		k += 1

func _take_chair() -> void:
	_walk(s().moba.king_pos(0) + Vector2(0.0, 2.8), 0.8)

func _stage_lane() -> void:
	# a minute in: walking up the middle lane behind our first wave, theirs coming down to meet it at the river
	_common(62.0, [0, 0], 380.0, ["greaves"], 2)
	var sm = s().moba
	sm.place_minions(0, 1, ["melee", "melee", "melee", "caster", "caster", "caster"], Vector2(0.0, 6.0))
	sm.place_minions(1, 1, ["melee", "melee", "melee", "caster", "caster", "caster"], Vector2(0.0, -3.5))
	_place(_u("you"), Vector2(1.5, 15.5), Vector2(0.0, 0.0))
	sturdy["you"] = 0.7

func _take_lane() -> void:
	_walk(Vector2(1.0, 8.0), 1.0)
	_after(1.3, func(): auto_attack = true)
	_after(3.4, func(): _press("ability"))

func _stage_fight() -> void:
	# three minutes in, the middle lane: their Barbarian, hurt, steps in on you -- your whole kit, and FIRST BLOOD
	_common(188.0, [0, 0], 640.0, ["greaves", "archon"], 6)
	s().moba.first_blood = false                  # (nobody's died yet: the first kill is FIRST BLOOD)
	var foe := _u("r0")
	s().moba.swap_hero(foe, "barbarian")
	_level(foe, 5)
	foe.max_hp = float(s().stat(foe, "hp"))
	foe.hp = 200.0
	_place(foe, Vector2(-1.0, -1.5), Vector2(0.0, 6.0))
	foe.bot = false
	_place(_u("you"), Vector2(0.5, 7.0), Vector2(0.0, -2.0))
	sturdy["you"] = 0.45
	var sm = s().moba
	sm.place_minions(0, 1, ["melee", "melee", "caster", "caster"], Vector2(0.0, 4.0))
	sm.place_minions(1, 1, ["melee", "melee", "caster"], Vector2(0.0, -5.0))

func _charge(id: String) -> void:
	# a foe of the take's own: at you, swinging when he's close
	var u := _u(id)
	if not s().alive(u) or not s().alive(_u("you")):
		return
	var d: Vector2 = (_u("you").pos as Vector2) - (u.pos as Vector2)
	u.face = s().angle_of(d.normalized())
	if d.length() > float(s().stat(u, "range")) + 0.6:
		u.move = d.normalized()
	else:
		u.move = Vector2.ZERO
		if s().can_act(u):
			s().act(id, "attack")

func _take_fight() -> void:
	for k in 60:
		_after(0.1 * float(k), func(): _charge("r0"))
	_after(0.3, func(): _press("ability"))           # CHAIN LIGHTNING
	_after(1.0, func(): _press("w"))                 # STATIC FIELD under him
	_after(1.5, func(): _press("attack"))
	_after(2.0, func(): _press("e"))                 # GUST
	_after(2.5, func(): auto_attack = true)
	_after(3.1, func(): _press("ult"))               # the storm

func _stage_death() -> void:
	# six minutes in: low on health, chasing their Golem under their own tower. He turns round.
	_common(380.0, [5, 4], 910.0, ["greaves", "archon"], 7)
	var tw := _red_tower(1, 1)
	var tp: Vector2 = tw.p
	var foe := _u("r1")
	s().moba.swap_hero(foe, "golem")
	_level(foe, 8)
	foe.max_hp = float(s().stat(foe, "hp"))
	foe.hp = foe.max_hp * 0.3
	_place(foe, tp + Vector2(1.5, 3.5), tp)
	foe.bot = true
	var me := _u("you")
	me.hp = float(me.max_hp) * 0.5
	_place(me, tp + Vector2(0.5, 12.5), tp)
	sturdy["you"] = 0.3

func _take_death() -> void:
	_walk(_red_tower(1, 1).p + Vector2(0.5, 4.5), 0.8)
	_after(0.6, func(): auto_attack = true)
	_after(1.2, func(): _press("ability"))
	_after(1.7, func():
		sturdy.erase("you")
		_u("you").hp = float(_u("you").max_hp) * 0.14)

func _stage_tower() -> void:
	# nine minutes in: their middle outer tower all but down, a wave of ours under it, you and a friend hitting it
	_common(545.0, [9, 7], 1320.0, ["archon", "greaves", "titan"], 9)
	var tw := _red_tower(1, 1)
	var tp: Vector2 = tw.p
	tw.hp = float(tw.max_hp) * 0.3
	_place(_u("you"), tp + Vector2(1.2, 9.0), tp)
	sturdy["you"] = 0.7
	s().moba.place_minions(0, 1, ["melee", "melee", "melee", "caster", "caster"], tp + Vector2(0.0, 7.0))

func _take_tower() -> void:
	_walk(_red_tower(1, 1).p + Vector2(1.0, 6.5), 0.8)
	_after(0.4, func(): auto_attack = true)

func _stage_wyrm() -> void:
	# fourteen minutes in: the Grave Wyrm up in its pit, three of ours on it (tools/store4_match.gd's)
	_common(870.0, [18, 15], 2140.0, ["archon", "greaves", "titan", "aegis"], 12)
	var sm = s().moba
	for c in sm.camps:
		if str(c.kind) == "wyrm":
			c.next = s().time
	var pit := Vector2(26.0, 3.9)
	var blue := _heroes(0)
	var n := 0
	for u in blue:
		if str(u.id) == "you" or n >= 2:
			continue
		_tough(u, 8.0, 0.8)
		_place(u, pit + Vector2(-6.0 + 5.0 * float(n), 6.5 - 1.0 * float(n)), pit)
		u.bot = true
		n += 1
	_place(_u("you"), pit + Vector2(-3.5, 10.5), pit)
	sturdy["you"] = 0.5

func _take_wyrm() -> void:
	_walk(Vector2(26.0, 3.9) + Vector2(-3.0, 7.5), 0.8)
	_after(1.0, func(): auto_attack = true)
	_after(2.2, func(): _press("ability"))
	_after(3.6, func(): _press("ult"))

func _stage_king() -> void:
	# eighteen minutes in: their keep open (the middle lane's towers, its gate and both King towers down), the King
	# on his chair, nearly done -- four of ours on him
	_common(1090.0, [27, 19], 3010.0, ["archon", "greaves", "titan", "aegis", "orb"], 14)
	var sm = s().moba
	for tw in sm.towers:
		if int(tw.team) == 1 and (int(tw.lane) == 1 or int(tw.tier) == 4):
			tw.hp = 0.0
			tw.dead = true
	for g in s().gates:
		if int(g.team) == 1 and int(g.get("lane", 1)) == 1:
			g.hp = 0.0
	(sm.kings[1] as Dictionary).hp = float((sm.kings[1] as Dictionary).max_hp) * 0.11
	for u in _heroes(1):
		u.pos = Vector2(-38.0, -12.0)                 # (out of the way: their fountain is right behind the King)
	var me0 := _u("you")
	me0.kills = 11
	me0.deaths = 2
	me0["towers"] = 3
	var king: Vector2 = sm.king_pos(1)
	var spots := [Vector2(3.2, 3.8), Vector2(-4.4, 2.6), Vector2(1.0, 3.0)]
	var n := 0
	for u in _heroes(0):
		if str(u.id) == "you" or n >= spots.size():
			continue
		_tough(u)
		_place(u, king + spots[n], king)
		u.bot = true
		n += 1
	_place(_u("you"), king + Vector2(-2.0, 10.0), king)
	sturdy["you"] = 0.6

func _take_king() -> void:
	var king: Vector2 = s().moba.king_pos(1)
	_walk(king + Vector2(-2.2, 6.0), 0.8)
	_after(0.9, func(): auto_attack = true)
