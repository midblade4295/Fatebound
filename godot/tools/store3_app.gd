extends SceneTree
# Play Store menu shots (0.31.116): the real app's screens with a mid-game profile, never the live server.
#   PART=forge|chest|friends|home OUT_DIR=<dir> DISPLAY=:98 godot --rendering-method mobile --fixed-fps 30 \
#       --resolution 1080x2400 --path . -s res://tools/store3_app.gd
# forge: the Forge on the Knight's legendary Kingsoath raised to three stars, fire picked (FORGE_PICK=<id> for another); chest: a Royal Chest opening (the burst,
# then the reveal -- its legendary, Final Verdict, the one a Royal Chest can drop); friends: the Friends window in a
# party, friends online (sample names: no server); home: Home in that party.
# Writes menu_<part>.png (chest: menu_chest_burst.png and menu_chest.png).
const App = preload("res://scripts/app/siege_app.gd")
const Screens = preload("res://scripts/app/screens.gd")
const Eco = preload("res://scripts/meta/economy.gd")

var app
var frames := 0
var part := "forge"
var dir := "/tmp/store3"
var pending := ""
var done_at := 120

func _init() -> void:
	if OS.has_environment("PART"):
		part = OS.get_environment("PART")
	if OS.has_environment("OUT_DIR"):
		dir = OS.get_environment("OUT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	var base := "user://store3app-%d" % Time.get_ticks_usec()
	app = App.new()
	app.eco_autostart = false
	app.social_autostart = false
	app.version_check = false
	app.profile_path = base + "-profile.json"
	app.legacy_path = base + "-none.json"
	app.now_override = 1791000000
	root.add_child(app)
	RenderingServer.frame_post_draw.connect(func():
		if pending != "":
			root.get_texture().get_image().save_png("%s/%s.png" % [dir, pending])
			print("SHOT ", pending)
			pending = "")

func _seed() -> void:
	var p = app.profile
	p.d.name = "Midblade"
	p.d.level = 14
	p.d.gold += 8400
	p.d.gems += 640
	p.d.embers = 520
	p.d.tutorial_done = true
	p.d.pass.xp = 12 * 2500 + 900
	for id in ["knight_wpn_greatsword", "knight_wpn_oath", "barb_wpn_spiked", "mage_wpn_crystal"]:
		if not p.d.owned.has(id):
			p.d.owned.append(id)
	p.equip("knight_wpn_oath")
	p.d.forge.stars["knight_wpn_oath"] = 3
	p.d.forge.element["knight_wpn_oath"] = "fire"
	p.d.forge.stars["knight_wpn_greatsword"] = 2
	p.d.forge.wins["knight_wpn_greatsword"] = 27
	p.d.stats.wins = 86
	p.d.stats.matches = 141
	for k in ["royal", "gold", "silver", "wooden"]:
		p.add_chest(k, {})
	p.d.chests.slots[0].start = p.now() - 999999
	p.d.chests.slots[1].start = p.now() - 3600
	p.save()

func _social() -> void:
	# a party of three, friends online: what the Friends window looks like with people in it (no server here)
	var s = app.social
	var me := {"pid":"3fa21c9b0d", "n":"Midblade", "tt":"title_siege_lord", "st":"online"}
	s.me = me.duplicate()
	s.state = "online"
	var f := [
		{"pid":"9c41e07a2b", "n":"SirKaylee", "tt":"title_shieldwall", "st":"online"},
		{"pid":"51ab90cc3e", "n":"BigBarb", "tt":"title_whirlwind", "st":"online"},
		{"pid":"e7d2214f80", "n":"MoonMage", "tt":"", "st":"match"},
		{"pid":"0b3f8a1d55", "n":"ArrowStorm", "tt":"title_brawler", "st":"online"},
		{"pid":"77c0d1e3aa", "n":"CakeBandit", "tt":"title_cake_baron", "st":"offline", "seen":int(Time.get_unix_time_from_system()) - 3 * 3600},
	]
	s.friends = f
	s.party = {"id":"pa1", "leader":me.pid, "members":[me, f[0], f[1]], "pending":[f[3]], "max":4}
	s.rin = [{"pid":"2d9e6b0f14", "n":"GateCrusher", "tt":"", "st":"online"}]
	s.lines.global = [{"n":"BigBarb", "x":"who's up for a siege?", "pid":"51ab90cc3e"}]
	s.changed.emit("state")
	s.changed.emit("friends")
	s.changed.emit("party")

func _process(_d: float) -> bool:
	frames += 1
	if frames == 3:
		_seed()
		app.rebuild()
	match part:
		"forge":
			if frames == 10:
				app.forge_cls = "knight"
				app.forge_pick = OS.get_environment("FORGE_PICK") if OS.has_environment("FORGE_PICK") else "knight_wpn_oath"
				app.forge_element = "fire"
				app.show_tab("forge")
			if frames == 55:
				pending = "menu_forge"
			done_at = 65
		"chest":
			if frames == 10:
				app.show_tab("home")
			if frames == 20:
				Screens.open_chest(app, 0)
			if frames == 50:
				app.modal.open()
			if frames == 50 + 40:                      # (before the rewards rise at 1.45 s: its legendary)
				app.modal.result["item"] = "crus_wpn_maul"
			if frames == 50 + 17:
				pending = "menu_chest_burst"
			if frames == 50 + 105:
				pending = "menu_chest"
			done_at = 50 + 115
		"friends":
			if frames == 10:
				_social()
				app.rebuild()
			if frames == 14:
				app.open_friends()
			if frames == 50:
				pending = "menu_friends"
			done_at = 60
		"home":
			if frames == 10:
				_social()
				app.rebuild()
			if frames == 55:
				pending = "menu_home"
			done_at = 65
	if frames > done_at:
		OS.kill(OS.get_process_id())                       # (the shots are on disk; Godot can hang on exit here)
	return false
