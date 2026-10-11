extends SceneTree
const Screens = preload("res://scripts/app/screens.gd")
# Dev tool: screenshots of the Siege app screens with a realistic mid-game test profile.
#   Xvfb :98 -screen 0 480x1000x24 & DISPLAY=:98 SHOT_DIR=/tmp/shots \
#   godot --rendering-method mobile --fixed-fps 30 --resolution 420x933 --path godot -s res://tools/app_shots.gd
# Env: SHOT_DIR (default /tmp/shots), SHOT_TABS (comma list, default all), SHOT_SCROLL (px to
# scroll each screen down for a second shot named <tab>_2).
const App = preload("res://scripts/app/siege_app.gd")
const Eco = preload("res://scripts/meta/economy.gd")
var app
var frames := 0
var tabs: Array = ["home", "pass", "shop", "locker", "settings"]
var dir := "/tmp/shots"
var scroll := 0
var pending := ""

func _init() -> void:
	if OS.has_environment("SHOT_DIR"): dir = OS.get_environment("SHOT_DIR")
	if OS.has_environment("SHOT_TABS"): tabs = OS.get_environment("SHOT_TABS").split(",")
	if OS.has_environment("SHOT_SCROLL"): scroll = int(OS.get_environment("SHOT_SCROLL"))
	DirAccess.make_dir_recursive_absolute(dir)
	var base := "user://appshot-%d" % Time.get_ticks_usec()
	var f := FileAccess.open(base + "-legacy.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"gold":820, "tokens":60, "owned":[0, 3], "chests":[{}], "level":7, "xp":10}))
	f.close()
	app = App.new()
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
		p.d.owned.append("knight_wpn_greatsword"); p.equip("knight_wpn_greatsword")
		if OS.has_environment("SHOT_FORGE"):            # 0.31.93: a profile mid-way through the Forge
			p.d.embers = 520
			p.d.gold += 6000
			p.d.forge.stars["knight_wpn_greatsword"] = 2
			p.d.forge.wins["knight_wpn_greatsword"] = 27
			p.d.owned.append("knight_wpn_oath")
			p.d.forge.stars["knight_wpn_oath"] = 3
			p.d.forge.element["knight_wpn_oath"] = "holy"
			app.forge_element = OS.get_environment("SHOT_FORGE")
			if OS.has_environment("SHOT_FORGE_CLS"):        # 0.31.94: another class's Forge (its weapons all owned)
				app.forge_cls = OS.get_environment("SHOT_FORGE_CLS")
				for id in Eco.CATALOG:
					if str(Eco.CATALOG[id].get("class", "")) == app.forge_cls and not p.d.owned.has(id):
						p.d.owned.append(id)
		if OS.has_environment("SHOT_QUESTS"):            # 0.31.97: some class quests under way, one step ready
			p.d.stats["q_knight_wins"] = 3
			p.d.stats["q_knight_rescues"] = 4
			p.d.stats["q_knight_kills"] = 61
			p.d.quests["ranger"] = 2
			p.d.stats["q_ranger_kills"] = 420
			p.d.quests["worker"] = 3
			p.d.owned.append("worker_wpn_sledge")
			app.quest_cls = OS.get_environment("SHOT_QUESTS")
		p.d.challenges.daily[0].progress = 99
		# (0.31.37) chests: one opening ready, one unlocking, two waiting
		for k in ["silver", "gold", "wooden", "royal"]:
			p.add_chest(k, {})
		p.d.chests.slots[0].start = p.now() - 99999
		p.d.chests.slots[1].start = p.now() - 3600
		p.save()
		app.rebuild()
	# 40 frames per tab: switch at +5, shot at +30 (lets the 3D showcase and animations settle),
	# optional scrolled shot at +38.
	for i in tabs.size():
		var base_f := 10 + i * 45
		if frames == base_f:
			app.show_tab(tabs[i])
			if tabs[i] == "locker" and OS.has_environment("SHOT_LOCKER"):
				app.locker_class = OS.get_environment("SHOT_LOCKER")
				app.rebuild()
		if frames == base_f + 18 and tabs[i] == "pass" and OS.has_environment("SHOT_PASS_DETAIL"):
			var pd: PackedStringArray = OS.get_environment("SHOT_PASS_DETAIL").split(",")
			Screens.open_pass_item(app, int(app.profile.d.pass.season), int(pd[0]), pd[1] == "prem")
		if frames == base_f + 12 and tabs[i] == "shop" and OS.has_environment("SHOT_PREVIEW"):
			# 0.31.96: the shop's tap-to-preview; "item_id" or "@pack_id,n"; SHOT_PREVIEW_MODE hand|weapon
			app.set_meta("shop_preview_mode", OS.get_environment("SHOT_PREVIEW_MODE") if OS.has_environment("SHOT_PREVIEW_MODE") else "hand")
			var pv := OS.get_environment("SHOT_PREVIEW")
			if pv.begins_with("@"):
				var pp := pv.substr(1).split(",")
				Screens.open_item(app, "", pp[0], int(pp[1]) if pp.size() > 1 else 0)
			else:
				Screens.open_item(app, pv)
		if frames == base_f + 21 and OS.has_environment("SHOT_ZOOM"):
			var zroot: Node = app.modal if app.modal != null else app          # (0.31.64: the locker's hero too)
			for c in zroot.find_children("*", "Control", true, false):
				if c.has_method("zoom_by"):
					c.zoom_by(float(OS.get_environment("SHOT_ZOOM")))
		if frames == base_f + 30: pending = tabs[i]
		if scroll > 0 and frames == base_f + 34: app.content_scroll.scroll_vertical = scroll
		if scroll > 0 and frames == base_f + 42: pending = tabs[i] + "_2"
	if frames > 10 + tabs.size() * 45 + 5: quit(0)
	return false
