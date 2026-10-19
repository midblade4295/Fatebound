extends SceneTree
# 0.31.187 (Kevin: "Make the champions the higher price since they are new. Also, give every champion a unique name that
# fits its class and character and give each one a short background story. Put all this in a revamped locker tab. When
# clicking on a champion, make a customized window for them that pops up that is themed around them and player can also
# zoom in and rotate them. Use art and effects that match each characters lore. Also put every skin that character has
# into that page that allows players to purchase or preview what it looks like"):
#  1. the eighteen: each a name of his own (none the same, none just his class), a title, a short story and a line; his
#     painting and card in the game, his colour, his effects' sprites all there; Champions.ORDER is the 5v5's order;
#  2. the Locker: CHAMPIONS first -- six roles, three cards each, each card his name, YOURS / FREE / NEW and a price;
#     ARMORY and TITLES as before (a class picked in locker_class picks ARMORY, "titles" TITLES);
#  3. a card tapped: his window -- his painting, his effects (moving), him in 3D (turned by a drag, zoomed by + / -), his
#     name, title, class and role, his story, his line and his kit; the launch price on a new one;
#  4. SKINS: his own look and every skin of his; a skin tapped is shown on him (PREVIEW, not bought); BUY asks first,
#     then it's his and worn; his own look again: WEAR; a locked hero's skin brings him;
#  5. UNLOCK in the window: the chooser (gold or gems), then he's yours; PLAY: the 5v5 window with him picked.
#   godot --headless --path godot -s res://tests/champions_test.gd   (SHOT_DIR=... under Xvfb for pictures)
const App = preload("res://scripts/app/siege_app.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const Moba = preload("res://scripts/siege/moba.gd")
const Kits = preload("res://scripts/siege/moba_kits.gd")
const Champions = preload("res://scripts/meta/champions.gd")
const ChampWindow = preload("res://scripts/app/champion_window.gd")
const Fx = preload("res://scripts/app/champion_fx.gd")
const HeroPanel = preload("res://scripts/app/moba_panel.gd")

var fails: Array = []
var phase := "data"
var t := 0.0
var t_phase := 0.0
var app
var shots := ""
var fx0 := {}
var yaw0 := 0.0
var zoom0 := 0.0

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

func _finish() -> bool:
	print("CHAMPIONS_PASS" if fails.is_empty() else "CHAMPIONS_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
	return true

func _data() -> void:
	# ---- 1. the eighteen
	check(Champions.ORDER == Moba.HERO_ORDER and Champions.CHAMPIONS.size() == 18, "eighteen champions, in the 5v5's order")
	var names := {}
	var shorts := {}
	var bad := []
	for hid in Moba.HERO_ORDER:
		var c: Dictionary = Champions.of(hid)
		var nm := str(c.get("name", ""))
		var cls := str(Moba.HEROES[hid].name)
		var lore := str(c.get("lore", ""))
		if (nm == "" or nm.to_lower() == cls.to_lower() or names.has(nm) or shorts.has(str(c.get("short", ""))) or str(c.get("title", "")) == ""
				or str(c.get("quote", "")) == "" or lore.length() < 120 or lore.length() > 330 or not nm.contains(str(c.get("short", "?")))):
			bad.append(hid)
		names[nm] = true
		shorts[str(c.get("short", ""))] = true
		if not ResourceLoader.exists(Champions.art(hid)) or not ResourceLoader.exists(Champions.card_art(hid)):
			bad.append(hid + " art")
		var fx: Array = c.get("fx", [])
		if fx.is_empty():
			bad.append(hid + " fx")
		for l in fx:
			if not ResourceLoader.exists(Fx.SPRITE % str(l[0])) or not (str(l[2]) in ["rise", "fall", "drift", "twinkle", "orbit", "halo", "rain", "flash", "meteor"]):
				bad.append("%s fx %s" % [hid, str(l)])
	check(bad.is_empty(), "each: his own name (not his class's, none twice), a title, a short story (120-330 letters) and a line; his painting, card and effects (%s)" % str(bad))
	var art: Texture2D = load(Champions.art("knight"))
	check(art != null and art.get_width() == 720 and art.get_height() == 1280, "the paintings: 720 x 1280 (9:16)")
	# ---- the launch price (Kevin: "Make the champions the higher price since they are new")
	var L := Eco.SIX_LAUNCH
	check(Eco.HERO_LAUNCH.size() == 6 and Eco.hero_price("stormcaller", L + 3 * 86400) == {"gold": Eco.LAUNCH_GOLD, "gems": Eco.LAUNCH_GEMS}
		and Eco.LAUNCH_GOLD == 2 * int(Eco.HERO_PRICES.stormcaller), "the six new ones at their launch price: 4,000 gold or 600 gems, twice their own")

func _app() -> void:
	var base := "user://champs-%d" % Time.get_ticks_usec()
	var p = Profile.new(base + "-profile.json", base + "-none.json")
	p.load_or_create()
	p.d.name = "Alice"
	p.d.tutorial_done = true
	p.d.gold = 1000
	p.d.gems = 2000
	p.save()
	app = App.new()
	app.profile_path = base + "-profile.json"
	app.legacy_path = base + "-none.json"
	root.add_child(app)

func _locked_new() -> String:
	# a new hero not free this week (so locked)
	for h in ["golem", "dragoon", "duelist", "stormcaller", "musketeer", "druid"]:
		if not app.profile.can_play_hero(h):
			return h
	return ""

func _process(delta: float) -> bool:
	t += delta
	t_phase += delta
	if t > 150.0:
		check(false, "timed out in phase %s" % phase)
		return _finish()
	match phase:
		"data":
			_data()
			_app()
			_go("boot")
		"boot":
			if t_phase > 1.0:
				# (in the six's launch, a week the Stormcaller isn't free)
				var at := Eco.SIX_LAUNCH + 3 * 86400
				if Eco.free_heroes(at).has("stormcaller"):
					at += 7 * 86400
				app.profile.now_override = at
				press("tab_locker")
				_go("locker")
		"locker":
			if t_phase > 0.5:
				# ---- 2. the Locker
				check(app.tab == "locker" and str(app.locker_tab) == "champions" and btn("locker_tab_champions") != null
					and btn("locker_tab_armory") != null and btn("locker_tab_titles") != null, "the Locker opens on CHAMPIONS; ARMORY and TITLES beside it")
				var n := 0
				for hid in Moba.HERO_ORDER:
					if btn("champ_" + str(hid)) != null:
						n += 1
				var roles := 0
				for r in Kits.ROLE_ORDER:
					if has_text(app.content, str(Kits.ROLE_NAMES[r])):
						roles += 1
				check(n == 18 and roles == 6, "18 cards under the six roles (%d, %d)" % [n, roles])
				var lk := _locked_new()
				check(lk != "" and has_text(btn("champ_knight"), "ALDRIC") and has_text(btn("champ_knight"), "YOURS")
					and has_text(btn("champ_" + lk), Champions.short_of(lk).to_upper()) and has_text(btn("champ_" + lk), "4,000")
					and has_text(btn("champ_" + lk), "NEW") and has_text(btn("champ_" + lk), "1 SKIN"),
					"a card: his name, YOURS -- or NEW at 4,000 (%s); his skins" % lk)
				var fr: String = Eco.free_heroes(app.profile.now())[0]
				check(has_text(btn("champ_" + fr), "FREE"), "this week's free one says FREE (%s)" % fr)
				_shot("champ_locker")
				press("locker_tab_armory")
				check(str(app.locker_tab) == "armory" and btn("locker_knight") != null and btn("locker_meet_knight") != null
					and has_text(app.content, "Sir Aldric Vane"), "ARMORY: the vault as before, his name on the nameplate, MEET ALDRIC")
				press("locker_tab_titles")
				check(str(app.locker_tab) == "titles" and str(app.locker_class) == "titles" and has_text(app.content, "NO TITLE"), "TITLES")
				app.locker_class = "mage"
				check(str(app.locker_tab) == "armory", "a class picked: the ARMORY")
				press("locker_tab_champions")
				press("champ_stormcaller")
				_go("window")
		"window":
			if t_phase > 1.2:
				# ---- 3. his window
				var w = app.modal
				check(w is ChampWindow and w.hero == "stormcaller", "a card tapped: his window")
				var bg: TextureRect = w._bg
				check(bg != null and bg.texture != null and str(bg.texture.resource_path).ends_with("champions/stormcaller.webp"),
					"his painting behind him (the storm-swept peak)")
				check(has_text(w, "TORVALD STORMCROWN") and has_text(w, "Voice of the Thunder") and has_text(w, "STORMCALLER")
					and has_text(w, "MAGE") and has_text(w, "the storm a question") and has_text(w, "The sky is answering")
					and has_text(w, "CHAIN LIGHTNING") and has_text(w, "THUNDERSTORM"), "his name, title, class, role, story, line and kit")
				check(has_text(w, "AT LAUNCH PRICE") and has_text(w, "4,000") and btn("champ_unlock") != null and btn("champ_play") == null,
					"new: at his launch price -- UNLOCK, no PLAY")
				var layers: Array = w.find_children("ChampionFx_*", "", true, false)
				var parts := 0
				for f in layers:
					parts += (f as Fx).count()
					fx0[f] = ((f as Fx).parts.duplicate(true))
				check(layers.size() >= 2 and parts >= 30, "his effects: rain, lightning and sparks (%d layers, %d sprites)" % [layers.size(), parts])
				var sh = w._show
				check(sh != null and sh.interactive and sh.body != null and sh.cls == "stormcaller", "him in 3D, to turn and zoom")
				yaw0 = sh._yaw
				zoom0 = sh._zoom_to
				var drag := InputEventScreenDrag.new()
				drag.relative = Vector2(80, 0)
				drag.position = sh.size * 0.5
				sh._gui_input(drag)
				press("champ_zoom_in")
				check(absf(sh._yaw - yaw0) > 0.5 and sh._zoom_to > zoom0, "a drag turns him, + zooms in")
				_shot("champ_window")
				_go("fx")
		"fx":
			if t_phase > 0.5:
				var moved := false
				for f in fx0:
					var before: Array = fx0[f]
					var now: Array = (f as Fx).parts
					for i in mini(before.size(), now.size()):
						if (before[i].p as Vector2).distance_to(now[i].p as Vector2) > 2.0:
							moved = true
				check(moved, "the effects move")
				_shot("champ_zoom")
				# ---- 4. SKINS
				var w = app.modal
				check(btn("champ_skin_default") != null and btn("champ_skin_stormcaller_frost") != null, "SKINS: his own look and the Frostbound")
				press("champ_zoom_out")
				press("champ_skin_stormcaller_frost")
				check(w.preview == "stormcaller_frost" and str(w._show.cosmetic.get("skin", "")) == "stormcaller_frost"
					and has_text(w, "PREVIEW") and not app.profile.owns_skin("stormcaller_frost") and has_text(w, "FROSTBOUND STORMCALLER"),
					"a skin tapped: shown on him -- a PREVIEW, not bought")
				_go("preview")
		"preview":
			if t_phase > 0.6:
				var w = app.modal
				_shot("champ_preview")
				w._scroll.scroll_vertical = 2000
				_go("scrolled")
		"scrolled":
			if t_phase > 0.4:
				var w = app.modal
				_shot("champ_story")
				press("champ_buy")
				check(w.overlay != null and has_text(w, "BUY FROSTBOUND STORMCALLER?") and has_text(w, "comes with it"),
					"BUY asks first (and says the hero comes with it)")
				var gems0 := int(app.profile.d.gems)
				press("champ_buy_yes")
				check(app.profile.owns_skin("stormcaller_frost") and app.profile.owns_hero("stormcaller") and app.profile.worn_skin("stormcaller") == "stormcaller_frost"
					and int(app.profile.d.gems) == gems0 - 750 and app.modal == w and w.overlay == null and has_text(w, "YOURS") and btn("champ_play") != null,
					"bought: the skin worn, the Stormcaller with it -- still his window, YOURS, PLAY")
				press("champ_skin_default")
				press("champ_wear")
				check(app.profile.worn_skin("stormcaller") == "" and has_text(w, "WORN"), "his own look again: WEAR")
				press("champ_close")
				_go("unlock")
		"unlock":
			if t_phase > 0.3:
				check(app.modal == null or not is_instance_valid(app.modal), "✕ shuts it")
				# ---- 5. UNLOCK and PLAY
				var lk := _locked_new()
				app.profile.d.gold = 5000
				app.open_champion(lk)
				press("champ_unlock")
				check(app.modal.overlay != null and btn("champ_unlock_gold") != null and btn("champ_unlock_gems") != null
					and has_text(app.modal, "4,000 GOLD"), "UNLOCK: the chooser -- 4,000 gold or 600 gems")
				press("champ_unlock_gold")
				check(app.profile.owns_hero(lk) and int(app.profile.d.gold) == 1000 and app.modal is ChampWindow and has_text(app.modal, "YOURS"),
					"4,000 gold: %s is yours" % Champions.name_of(lk))
				press("champ_play")
				check(app.modal is HeroPanel and app.modal.hero == lk, "PLAY: the 5v5 window with him picked")
				app.close_modal()
				return _finish()
	return false
