extends SceneTree
const Screens = preload("res://scripts/app/screens.gd")
# Dev tool: screenshots of the Siege app screens with a realistic mid-game test profile.
#   Xvfb :98 -screen 0 480x1000x24 & DISPLAY=:98 SHOT_DIR=/tmp/shots \
#   godot --rendering-method mobile --fixed-fps 30 --resolution 420x933 --path godot -s res://tools/app_shots.gd
# Env: SHOT_DIR (default /tmp/shots), SHOT_TABS (comma list, default all), SHOT_SCROLL (px to
# scroll each screen down for a second shot named <tab>_2), SHOT_SWING (0.31.113: with SHOT_TABS=home and --fixed-fps 30,
# this many frames of Home after its shot, one every 2nd frame: home_swing_NN), SHOT_MENU=1 (0.31.139: Home with the
# level shield's menu open).
const App = preload("res://scripts/app/siege_app.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const PlayGames = preload("res://scripts/meta/play_games.gd")

class ShotPlay extends Node:                     # a stand-in for the Play Games plugin (SHOT_PLAY)
	signal userAuthenticated(ok: bool)
	signal currentPlayerLoaded(json: String)
	signal gameLoaded(json: String)
	signal gameSaved(ok: bool, name: String, desc: String)
	signal conflictEmitted(json: String)
	var signed := true
	var bytes := PackedByteArray()
	func initialize() -> void: pass
	func isAuthenticated() -> void: userAuthenticated.emit(signed)
	func signIn() -> void: userAuthenticated.emit(true)
	func loadCurrentPlayer(_f: bool) -> void: currentPlayerLoaded.emit(JSON.stringify({"displayName":"Midblade"}))
	func loadGame(_n: String, _c: bool) -> void: gameLoaded.emit("null" if bytes.is_empty() else JSON.stringify({"content":Array(bytes)}))
	func saveGame(n: String, d: String, b: PackedByteArray, _t: int, _p: int) -> void:
		bytes = b
		gameSaved.emit(true, n, d)
var app
var frames := 0
var tabs: Array = ["home", "pass", "shop", "locker", "settings"]
var dir := "/tmp/shots"
var scroll := 0
var pending := ""
var swing := 0

func _init() -> void:
	if OS.has_environment("SHOT_DIR"): dir = OS.get_environment("SHOT_DIR")
	if OS.has_environment("SHOT_TABS"): tabs = OS.get_environment("SHOT_TABS").split(",")
	if OS.has_environment("SHOT_SCROLL"): scroll = int(OS.get_environment("SHOT_SCROLL"))
	if OS.has_environment("SHOT_SWING"): swing = int(OS.get_environment("SHOT_SWING"))
	DirAccess.make_dir_recursive_absolute(dir)
	var base := "user://appshot-%d" % Time.get_ticks_usec()
	var f := FileAccess.open(base + "-legacy.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"gold":820, "tokens":60, "owned":[0, 3], "chests":[{}], "level":7, "xp":10}))
	f.close()
	app = App.new()
	# 0.31.112: never the live server -- with a display the app would make an account there (eco_sync) and replace this
	# profile with it, and open a social socket
	app.eco_autostart = false
	app.social_autostart = false
	app.version_check = false
	app.profile_path = base + "-profile.json"
	app.legacy_path = base + "-legacy.json"
	app.now_override = 1791000000
	root.add_child(app)
	RenderingServer.frame_post_draw.connect(func():
		if pending != "":
			root.get_texture().get_image().save_png("%s/%s.png" % [dir, pending])
			pending = "")

func _process(_d: float) -> bool:
	frames += 1
	if frames == 3:
		var p = app.profile
		p.d.gems += 400
		p.d.pass.xp = 7 * 2500 + 900
		# (0.31.93-0.31.187: a weapon equipped, SHOT_FORGE a profile mid-way through the Forge -- gone, 0.31.188)
		if OS.has_environment("SHOT_QUESTS"):            # 0.31.97: some class quests under way, one step ready
			p.d.stats["q_knight_wins"] = 3
			p.d.stats["q_knight_rescues"] = 4
			p.d.stats["q_knight_kills"] = 61
			p.d.quests["ranger"] = 2
			p.d.stats["q_ranger_kills"] = 420
			p.d.quests["worker"] = 3
			app.quest_cls = OS.get_environment("SHOT_QUESTS")
		if OS.has_environment("SHOT_EQUIP"):             # 0.31.100: wear these (owned for the shot; 0.31.188: outfits)
			for id in OS.get_environment("SHOT_EQUIP").split(","):
				if Eco.SKINS.has(id):
					if not p.d.skins.has(id):
						p.d.skins.append(id)
					p.wear_skin(str(Eco.SKINS[id].hero), id)
		if OS.has_environment("SHOT_PLAY"):              # 0.31.102: Settings' Google Play card: out | synced | ask
			var fp := ShotPlay.new()
			fp.signed = OS.get_environment("SHOT_PLAY") != "out"
			if OS.get_environment("SHOT_PLAY") == "ask":
				var other := Profile.new("user://shot_other_%d.json" % Time.get_ticks_usec(), "user://none.json")
				other.load_or_create()
				other.d.gold = 4321
				other.d.gems = 260
				other.d.level = 23
				other.d.stats.wins = 140
				other.d.stats.matches = 260
				fp.bytes = PlayGames.encode(other.cloud_payload("other-1", "SM-G998U"))
				p.d.cloud.stamp = "mine-1"
			root.add_child(fp)
			app.play_games.setup(p, fp)
		if OS.has_environment("SHOT_TUTORIAL"):          # 0.31.112: Home before / after the tutorial (todo | done)
			p.d.tutorial_done = OS.get_environment("SHOT_TUTORIAL") == "done"
		p.d.challenges.daily[0].progress = 99
		# (0.31.37) chests: one opening ready, one unlocking, two waiting
		if not OS.has_environment("SHOT_NO_CHESTS"):     # 0.31.117: SHOT_NO_CHESTS=1 -- a new player's empty slots
			for k in ["silver", "gold", "wooden", "royal"]:
				p.add_chest(k, {})
			p.d.chests.slots[0].start = p.now() - 99999
			p.d.chests.slots[1].start = p.now() - 3600
		if OS.has_environment("SHOT_QUEUE"):             # 0.31.108: reward chests waiting for a slot
			p.d.chests.queue = ["royal", "gold"]
		p.save()
		app.rebuild()
	# 40 frames per tab: switch at +5, shot at +30 (lets the 3D showcase and animations settle),
	# optional scrolled shot at +38.
	for i in tabs.size():
		var base_f := 10 + i * 45
		if frames == base_f:
			app.show_tab(tabs[i])
			if tabs[i] == "locker" and OS.has_environment("SHOT_LOCKER"):
				app.locker_tab = OS.get_environment("SHOT_LOCKER")       # champions | titles
				app.rebuild()
		if frames == base_f + 12 and tabs[i] == "home" and OS.has_environment("SHOT_MENU"):
			app.open_player_menu()                       # 0.31.139: the menu under the level shield
		if frames == base_f + 18 and tabs[i] == "pass" and OS.has_environment("SHOT_PASS_DETAIL"):
			var pd: PackedStringArray = OS.get_environment("SHOT_PASS_DETAIL").split(",")
			Screens.open_pass_item(app, int(app.profile.d.pass.season), int(pd[0]), pd[1] == "prem")
		if frames == base_f + 12 and tabs[i] == "shop" and OS.has_environment("SHOT_PREVIEW"):
			app.open_champion(str(Eco.SKINS[OS.get_environment("SHOT_PREVIEW")].hero), OS.get_environment("SHOT_PREVIEW"))     # 0.31.188: an outfit
		if frames == base_f + 12 and tabs[i] == "home" and OS.has_environment("SHOT_ORDERS"):
			app.open_orders()                            # 0.31.112: the ORDERS window
		if frames == base_f + 12 and tabs[i] == "home" and OS.has_environment("SHOT_MOBA"):
			app.open_moba()                              # 0.31.171: the hero window (SHOT_MOBA=<hero>: that one picked)
			if app.modal != null and OS.get_environment("SHOT_MOBA") != "1":
				app.modal.hero = OS.get_environment("SHOT_MOBA")
				app.modal._render()
		if frames == base_f + 21 and OS.has_environment("SHOT_ZOOM"):
			var zroot: Node = app.modal if app.modal != null else app          # (0.31.64: the locker's hero too)
			for c in zroot.find_children("*", "Control", true, false):
				if c.has_method("zoom_by"):
					c.zoom_by(float(OS.get_environment("SHOT_ZOOM")))
		if frames == base_f + 30: pending = tabs[i]
		if scroll > 0 and frames == base_f + 34: app.content_scroll.scroll_vertical = scroll
		if scroll > 0 and frames == base_f + 42: pending = tabs[i] + "_2"
	if swing > 0 and frames > 41 and frames <= 41 + swing * 2 and (frames - 41) % 2 == 0:
		pending = "home_swing_%02d" % ((frames - 41) / 2 - 1)
	if frames > maxi(10 + tabs.size() * 45 + 5, 41 + swing * 2 + 5): quit(0)
	return false
