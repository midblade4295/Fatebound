extends SceneTree
# 0.31.200 (Kevin: "Need all new pics for app stores"): the store screenshots' app screens -- the real app with a
# mid-game profile, never the live server (SIEGE_URL unreachable; the friends, party and clan are sample data, drawn by
# the app's own windows as the server's answers would have them).
#   PART=home|champion|outfit|clan|chest|tutorial|herald  OUT=<png>
#   DISPLAY=:97 FB_FORCE_HQ=1 godot --rendering-method mobile --fixed-fps 30 --resolution 1080x2400 --path . \
#     -s res://tools/store4_app.gd
# home: Home (the champions' camp) in a party, chests in the slots; champion: the Stormcaller's window in his
# Stormforged outfit; outfit: the Mage's window in Phoenix; clan: the clan camp (stage 4) with its buttons; chest: a
# chest opening (a hero shard); tutorial: the 5v5 tutorial, the Herald's first line on his scroll; herald: the Herald's
# welcome on Home, showing PLAY.
const App = preload("res://scripts/app/siege_app.gd")
const Screens = preload("res://scripts/app/screens.gd")
const Eco = preload("res://scripts/meta/economy.gd")

var app
var frames := 0
var part := "home"
var out := "/tmp/store4_app.png"
var pending := false
var done_at := 400
var _t0 := -1

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")
	part = OS.get_environment("PART") if OS.has_environment("PART") else part
	out = OS.get_environment("OUT") if OS.has_environment("OUT") else out
	var base := "user://store4app-%d" % Time.get_ticks_usec()
	app = App.new()
	app.eco_autostart = false
	app.social_autostart = false
	app.version_check = false
	app.profile_path = base + "-profile.json"
	app.legacy_path = base + "-none.json"
	app.now_override = 1791000000
	root.add_child(app)
	RenderingServer.frame_post_draw.connect(func():
		if pending:
			pending = false
			root.get_texture().get_image().save_png(out)
			print("STORE4_APP_SHOT ", part, " ", out)
			done_at = frames + 2)

func _seed() -> void:
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
	for h in ["stormcaller", "dragoon", "golem", "duelist"]:
		if not (p.d.get("heroes", []) as Array).has(h):
			(p.d.heroes as Array).append(h)
	for k in ["royal", "gold", "silver", "wooden"]:
		p.add_chest(k, {})
	p.d.chests.slots[0].start = p.now() - 999999
	p.d.chests.slots[1].start = p.now() - 3600
	p.save()

func _social(with_clan: bool) -> void:
	# friends online, a party of three, and (with_clan) the Iron Wolves at level 8 (the camp's last stage)
	var s = app.social
	var me := {"pid":"3fa21c9b0d", "n":"Midblade", "tt":"", "st":"online", "ct":"WOLF", "cc":"3.5.1"}
	s.me = me.duplicate()
	s.state = "online"
	s.has_clans = true
	var f := [
		{"pid":"9c41e07a2b", "n":"Ironclad", "tt":"", "st":"online", "ct":"WOLF", "cc":"3.5.1"},
		{"pid":"51ab90cc3e", "n":"Mirabel", "tt":"", "st":"online"},
		{"pid":"e7d2214f80", "n":"Thornwick", "tt":"", "st":"match", "ct":"WOLF", "cc":"3.5.1"},
		{"pid":"0b3f8a1d55", "n":"Kaelen", "tt":"", "st":"online"},
		{"pid":"77c0d1e3aa", "n":"Pyra", "tt":"", "st":"offline", "seen":1791000000 - 3 * 3600},
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
			"members":members, "role":"leader", "created":1789000000, "xp":7900, "week":"2026-W42", "ends":1791000000 + 3 * 86400,
			"tier":Eco.clan_tier(2460), "mine_pts":420, "asks":[{"pid":"m05", "n":"Vex", "h":"golem", "at":1791000000 - 1200}],
			"ask_next":0, "lfg":[{"pid":"m04", "n":"Odessa", "at":1791000000 - 60, "size":2, "max":5}]}
	s.changed.emit("state")
	s.changed.emit("friends")
	s.changed.emit("party")
	if with_clan:
		s.changed.emit("clan")

func _process(_d: float) -> bool:
	frames += 1
	if frames == 3:
		_seed()
		app.rebuild()
	match part:
		"home":
			if frames == 10:
				_social(true)
				app.rebuild()
			if frames == 70:
				pending = true
		"champion", "outfit":
			if frames == 10:
				_social(false)
				if part == "champion":
					app.open_champion("stormcaller", "stormcaller_stormforged")
				else:
					app.open_champion("mage", "mage_phoenix")
			if frames == 130:
				pending = true
		"clan":
			if frames == 10:
				_social(true)
				app.rebuild()
			if frames == 14:
				app.open_clan()
			if frames == 120:
				pending = true
		"chest":
			if frames == 10:
				app.show_tab("home")
			if frames == 20:
				Screens.open_chest(app, 0)
			if frames == 50:
				app.modal.open()
			if frames == 50 + 40:                      # (before the rewards rise at 1.45 s: a hero shard)
				app.modal.result["shard"] = "dragoon"
			if frames == 50 + 105:
				pending = true
		"herald":
			if frames == 10:
				app.profile.d.name = "Player"
				app.rebuild()
			if frames == 20:
				app.open_intro()
			if frames == 30:
				var it = app.modal
				it.shown = 9999.0
				it.next()
				it.submit_name("Midblade")
				for i in 3:
					it.shown = 9999.0
					it.next()
			if frames == 110:
				app.modal.shown = 9999.0
				pending = true
		"tutorial":
			if frames == 10:
				app.start_tutorial()
			if app.siege != null and _t0 < 0 and app.siege.tutorial_ui != null and str(app.siege.tutorial_ui.phase) == "talk":
				_t0 = frames
			if _t0 > 0 and frames == _t0 + 140:
				app.siege.tutorial_ui.shown = 9999.0
				pending = true
			done_at = maxi(done_at, frames + 5) if _t0 < 0 and frames < 1500 else done_at
	if frames > done_at:
		OS.kill(OS.get_process_id())                       # (the shot is on disk; Godot can hang on exit here)
	return false
