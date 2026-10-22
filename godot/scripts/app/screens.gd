extends RefCounted
# Screens for the Siege app shell. Each builds into `root` from app.profile; the shell rebuilds
# the current screen after every change (buy, claim, equip...).
const UI = preload("res://scripts/app/ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")
const ChestRow = preload("res://scripts/app/chest_row.gd")
const ChestOpen = preload("res://scripts/app/chest_open.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const View = preload("res://scripts/siege/siege_view.gd")
const Showcase = preload("res://scripts/app/showcase.gd")
const Diag = preload("res://scripts/siege/siege_diag.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
const Platform = preload("res://scripts/meta/platform.gd")          # 0.31.130: Google Play or the App Store
const StoreBilling = preload("res://scripts/meta/store_billing.gd")
const Champions = preload("res://scripts/meta/champions.gd")       # 0.31.187: who the eighteen are (the Locker)

const PRIVACY_URL := "https://136-113-125-3.sslip.io/fatebound/privacy.html"

# ---------------- shared bits ----------------
static func section(root: Node, text: String, right := "", icon := "") -> void:
	var r := UI.row(root, 8)
	if icon != "":
		UI.icon(r, icon, 18, UI.GOLD)
	UI.grow(UI.label(r, text, 15, UI.GOLD, UI.TITLE_FONT, true))
	if right != "":
		var l := UI.label(r, right, 12, UI.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF

static func item_icon(it: Dictionary) -> String:
	return "title" if str(it.get("kind", "")) == "title" else "star"

static func rarity(it: Dictionary) -> Color:
	return Color(str(Eco.RARITY_COLOR.get(str(it.get("rarity", "common")), "#b8c4c9")))

static func chest_icon(kind: String) -> String:
	return UI2.V2 + "chests/%s_icon.png" % str({"wooden": "wood"}.get(kind, kind))

const HERO_NAMES := {"golem":"Golem", "dragoon":"Dragoon", "duelist":"Duelist", "stormcaller":"Stormcaller", "musketeer":"Musketeer",
	"druid":"Druid"}                     # (moba.gd HEROES' names for the sold ones -- this file doesn't load the sim)

static func reward_text(r: Dictionary) -> Array:
	# -> [glyph kind, text, colour, texture path or ""]
	if r.has("chest"):                                   # (0.31.79: chests used to read "0 gold" here)
		var ck := str(r.chest)
		return ["chest", str(Eco.CHESTS.get(ck, {}).get("name", "Chest")), Color(str(Eco.CHESTS.get(ck, {}).get("color", "#ffcf4a"))), chest_icon(ck)]
	if r.has("gems"):
		return ["gem", "%d gems" % int(r.gems), UI.CYAN, "res://assets/ui/currency/gem.png"]
	# 0.31.185 (League's way): a hero shard (which hero, once it's known) and the premium pass's Hero Token
	if r.has("shard"):
		var sh := str(r.shard)
		if sh != "":
			return ["star", "%s Shard" % str(HERO_NAMES.get(sh, sh.capitalize())), Color("#9dff8a"), "res://assets/ui/skins/default_%s.png" % sh]
		return ["star", "Hero Shard", Color("#9dff8a"), UI2.V2 + "icons/helmet.png"]
	if r.has("token"):
		return ["star", "Hero Token", Color("#e2b8ff"), UI2.V2 + "icons/helmet.png"]
	var g := int(r.get("gold", 0))
	return ["coin", "%d gold" % g, UI.GOLD, "res://assets/ui/currency/%s.png" % ("coins_s" if g >= 300 else "coin")]

static func _rar_panel(rar: String) -> String:
	return {"common": "night", "rare": "royal", "epic": "purple", "legendary": "ember"}.get(rar, "night")

static func _rar_rim(rar: String) -> String:
	return {"common": "silver", "rare": "blue", "epic": "purple", "legendary": "orange"}.get(rar, "gold")

static func _rar_tint(rar: String) -> Color:
	return {"common": Color(0.85, 0.88, 1.0), "rare": Color(0.55, 0.78, 1.0), "epic": Color(0.85, 0.6, 1.0), "legendary": Color(1.0, 0.78, 0.35)}.get(rar, Color(1, 0.9, 0.6))

# ---------------- HOME ----------------
# 0.31.79 (Kevin: the concepts, "build it"): the painted backdrop with the heroes (the app's hero layer), one big PLAY
# (always the server), the chests in 3D. The top is laid out by hand in content pixels (the hero layer lines up with it).
# 0.31.112 (Kevin: "for home screen I don't want it to scroll down, just have the chests at bottom and move the orders and
# stuff to its own popup menu"): Home fills the screen and doesn't scroll, the chests on the bottom edge; on a screen too
# short for it, Home scrolls the little that's left.
# 0.31.194 (Kevin: "Now let's design a new home screen" -- he picked B2, the champions' camp, keeping the chest slots, the
# chat bar and the Discord / server pill): top to bottom -- the 5v5 pill (or your party) and JOIN OUR DISCORD in one row
# under the top bar; the camp (camp_scene.gd: six champions round their fire); PLAY, an orange enamel plaque in a gold
# frame with a blue gem at each end, the first win of the day as a tab under it; the four chests, each on a dark wood
# panel with its name, the chest in 3D and its button; then the chat line and the tabs (siege_app). The side buttons
# are gone: PASS has its tab, and ORDERS, QUESTS, RANKS and the TUTORIAL are in the top bar's menu (siege_app
# open_home_menu). (0.31.114-0.31.193: medallion columns down both sides -- PASS, ORDERS, QUESTS; RANKS, TUTORIAL.)
const ROW_Y := 2.0             # the top row: the 5v5 pill (or your party) and JOIN OUR DISCORD
const ROW_H := 40.0
const DISCORD_W := 118.0
const SALE := "res://assets/ui/v2/sale/"       # 0.31.203: the weekly sale's art (ElevenLabs): stage, ribbon, starburst
const SALE_FEET := 0.78        # where the showcase stands him (of the stage's height): the pedestal goes under his feet
const PLAQUE := "res://assets/ui/v2/play_plaque.webp"
const PLAQUE_W := 250.0
const PLAQUE_H := 84.0         # (760 x 255 art: tools/home_camp.py; 0.31.139-0.31.193 a plaque with a crown and swords)
const PLAQUE_FACE := Rect2(0.13, 0.18, 0.74, 0.7)    # the enamel face, as fractions of the plaque
const FW_H := 26.0             # the FIRST WIN tab under PLAY ...
const FW_HANG := 14.0          # ... hanging this far below the plaque
const PLAY_GAP := 6.0          # between PLAY (its tab) and the chests
const PLAY_MIN := 260.0        # (on a short screen PLAY goes no higher: Home scrolls a little instead)
const CHEST_H := 104.0         # a chest's panel: its name, the chest in 3D, its button
const CHEST_FILL := [Color("#3b2717"), Color("#140b05")]     # the panels' dark wood (top, bottom)

static func discord_press(app) -> void:
	# 0.31.124/125: Settings' and Home's JOIN OUR DISCORD -- open the invite; the first time, the gift (once per account)
	app.open_url.call(Eco.DISCORD_URL)              # (the app's link opener; tests put their own)
	if bool(app.profile.d.get("discord", false)):
		app.sfx("tap")
		return
	var r: Dictionary = app.profile.claim_discord()
	if bool(r.get("ok", false)):
		app.sfx("purchase")
		app.toast("Thanks for joining! +%d gems" % Eco.DISCORD_GEMS, UI.GOLD)
		app.refresh_top()
		app.rebuild()                                # (Home's button goes; Settings' loses its +100)

static func home_layout(h: float) -> Dictionary:
	# the chests on the bottom edge, PLAY (and its tab) just over them; on a short screen PLAY goes no higher than
	# PLAY_MIN and Home scrolls a little
	var chest_y := h - CHEST_H - 4.0
	var play := chest_y - PLAY_GAP - FW_HANG - PLAQUE_H
	if play < PLAY_MIN:
		play = PLAY_MIN
		chest_y = play + PLAQUE_H + FW_HANG + PLAY_GAP
	return {"play": play, "chests": chest_y, "needed": chest_y + CHEST_H + 4.0}

static func menu_counts(app) -> Dictionary:
	# 0.31.194: what's waiting in the top bar's menu -- the orders ready to claim (the daily login reward counts: 0.31.119)
	# and the quest steps ready (0.31.97); whether the tutorial's been played
	var p = app.profile
	var d: Dictionary = p.d
	var orders := 1 if p.login_ready() else 0
	for span in ["daily", "weekly"]:
		for ch in (d.challenges.daily if span == "daily" else d.challenges.weekly):
			if not bool(ch.claimed) and Eco.CHALLENGES.has(str(ch.id)) and int(ch.progress) >= int(Eco.CHALLENGES[ch.id].goal):
				orders += 1
	return {"orders": orders, "quests": int(p.quests_ready()), "tutorial_done": bool(d.get("tutorial_done", false))}

static func home(app, root: VBoxContainer) -> void:
	var p = app.profile
	var d: Dictionary = p.d
	app.hero_show()
	var w: float = maxf(300.0, app.size.x - 24.0)
	var avail: float = app.home_height()
	var lay := home_layout(avail)
	app.home_fixed = float(lay.needed) <= avail + 1.0
	var top := Control.new()
	top.custom_minimum_size = Vector2(0, maxf(avail, float(lay.needed)))
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	if d.has("title_note"):                               # 0.31.87: titles earned from the stats you already had
		var tn: Array = d.title_note
		app.toast("You've earned %d title%s for what you've already done -- see the Armory" % [tn.size(), "" if tn.size() == 1 else "s"], UI.GOLD)
		d.erase("title_note")
		p.save()
	if d.has("refund_note"):                              # 0.31.39: skins removed -- tell them once what came back
		var rn: Dictionary = d.refund_note
		app.toast("Skins have been retired -- refunded %s" % ", ".join([("%d gold" % int(rn.gold)) if int(rn.gold) > 0 else "", ("%d gems" % int(rn.gems)) if int(rn.gems) > 0 else ""].filter(func(x): return x != "")), UI.GOLD)
		d.erase("refund_note")
		p.save()
	var soc = app.get("social")
	var fw_open := str(d.first_win_day) != Eco.day_key(p.now())
	# --- the top row: the 5v5 pill (or your party) on the left, JOIN OUR DISCORD on the right until it's claimed
	# (0.31.125, Kevin: "Put a discord button on front page that goes away after they claim it")
	var discord := not bool(d.get("discord", false))
	var left_w := w - (DISCORD_W + 8.0 if discord else 0.0)
	if soc != null and soc.online() and soc.in_party():
		# in a party: who's in it (the leader first, with a crown)
		var names := []
		for m in soc.party.get("members", []):
			names.append(("♛ " if str(m.pid) == str(soc.party.leader) else "") + str(m.n))
		var pb := UI2.button(top, "PARTY %d/%d  ·  %s" % [soc.party_size(), int(soc.party.get("max", 4)), "  ·  ".join(names)], "green", func():
			app.sfx("menuOpen")
			app.open_friends(), "party_pill", 12, ROW_H, 17.0)
		pb.position = Vector2(0, ROW_Y)
		pb.size = Vector2(left_w, ROW_H)
		pb.clip_text = true
		app.online_refs = {}
	else:
		_online_pill(app, top, Rect2(0, ROW_Y, left_w, ROW_H), not discord)
	if discord:
		_discord_button(app, top, Rect2(w - DISCORD_W, ROW_Y, DISCORD_W, ROW_H))
	# --- PLAY: always the Siege server (0.31.79); the bots fill any empty slots. 0.31.145: it opens the 5v5's heroes.
	var py: float = lay.play
	var px := (w - PLAQUE_W) * 0.5
	UI2.glow(top, Rect2(px - 34, py - 12, PLAQUE_W + 68, PLAQUE_H + 30), Color(1.0, 0.55, 0.15, 0.5))
	var play := Button.new()
	play.flat = true
	play.focus_mode = Control.FOCUS_NONE
	for st_name in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
		play.add_theme_stylebox_override(st_name, StyleBoxEmpty.new())
	play.position = Vector2(px, py)
	play.size = Vector2(PLAQUE_W, PLAQUE_H)
	play.set_meta("action_key", "play")
	play.pressed.connect(func(): app.play())
	top.add_child(play)
	var art := TextureRect.new()
	art.name = "Plaque"
	art.texture = UI2.tex(PLAQUE)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play.add_child(art)
	if art.texture == null:                         # (without the ui pack's art: an orange button's colours)
		UI2.plate(art, "orange", 18.0, "gold")
	var word := "PLAY"                            # (0.31.164-169: the 5v5 offline, no party count)
	if soc != null and soc.online() and soc.in_party() and soc.is_leader() and soc.party_size() > 1:
		word = "PLAY ×%d" % soc.party_size()       # 0.31.170: the online 5v5 -- the party goes in together
	var face := Rect2(PLAQUE_FACE.position * play.size, PLAQUE_FACE.size * play.size)
	var pl := UI2.text(play, word, 42 if word.length() <= 5 else 34, Color.WHITE, Color("#6a1a04"), 11)
	pl.name = "PlayWord"
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pl.position = face.position + Vector2(0, 1)
	pl.size = face.size
	pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI2.sweep(play, 3.4, 60.0, 0.4)
	UI2.pulse(play, 0.022, 1.1)
	if fw_open:
		# 0.31.119: the first win of the day (it was the FIRST WIN medallion); 0.31.194 a dark tab hanging under PLAY
		var tag := _first_win_tab(top)
		tag.position = Vector2((w - tag.size.x) * 0.5, py + PLAQUE_H + FW_HANG - FW_H)
	# --- chests, on the bottom edge
	chests_row(app, top, w, float(lay.chests))
	if bool(app.get("safe_boot")) and not bool(app.get_meta("safe_note", false)):
		# 0.31.70: the last start never reached the menu, so this one skipped the background loading
		app.set_meta("safe_note", true)
		app.toast("The game got stuck starting last time -- please tap Settings > SEND TO DEVELOPER", UI.GOLD)

static func _first_win_tab(parent: Control) -> Control:
	# 0.31.194: FIRST WIN +150 and a coin, white and gold on a dark tab with a gold rim (B2's)
	var tab := Control.new()
	tab.name = "FirstWinTag"
	tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(tab)
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 5)
	r.alignment = BoxContainer.ALIGNMENT_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab.add_child(r)
	var a := UI2.text(r, "FIRST WIN", 13, Color.WHITE, UI2.INK, 4)
	a.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var b := UI2.text(r, "+%d" % int(Eco.FIRST_WIN.gold), 14, UI2.GOLD, UI2.INK, 4)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UI2.img(r, "res://assets/ui/currency/coin.png", 18.0).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tw := (UI2.LG as Font).get_string_size("FIRST WIN", HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x \
		+ (UI2.LG as Font).get_string_size("+%d" % int(Eco.FIRST_WIN.gold), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 18.0 + 10.0 + 30.0
	tab.size = Vector2(tw, FW_H)
	r.position = Vector2.ZERO
	r.size = tab.size
	UI2.plate(tab, "night", 11.0, "gold", {"fill_top": Color("#3a2414"), "fill_bottom": Color("#160c05"), "rim": 2.0,
		"shadow_y": 3.0})
	UI2.bob(tab, 1.5, 1.4)
	return tab

static func _discord_button(app, top: Control, at: Rect2) -> void:
	# 0.31.125: JOIN OUR DISCORD, its gift as a tag on its corner, until it's claimed (0.31.194: on the top row's right,
	# two lines, as B2 has it)
	var db := UI2.button(top, "JOIN OUR\nDISCORD", "discord", func(): discord_press(app), "home_discord", 11, at.size.y, 14.0)
	db.name = "HomeDiscord"
	db.position = at.position
	db.size = at.size
	db.add_theme_constant_override("line_spacing", -4)
	UI2.bob(db, 2.0, 1.8)
	var gt := PanelContainer.new()
	gt.name = "DiscordGift"
	var gs := StyleBoxFlat.new()
	gs.bg_color = Color("#ffc94d")
	gs.border_color = Color("#3a1c02")
	gs.set_border_width_all(2)
	gs.set_corner_radius_all(10)
	gs.content_margin_left = 6
	gs.content_margin_right = 8
	gs.shadow_color = Color(0, 0, 0, 0.35)
	gs.shadow_size = 4
	gt.add_theme_stylebox_override("panel", gs)
	gt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	db.add_child(gt)
	var gr := HBoxContainer.new()
	gr.add_theme_constant_override("separation", 3)
	gr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gt.add_child(gr)
	UI2.img(gr, "res://assets/ui/currency/gem.png", 16.0).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var gl := Label.new()                          # (a plain Label: a wrapping one sizes the tag a letter wide)
	gl.text = "+%d" % Eco.DISCORD_GEMS
	gl.add_theme_font_override("font", UI.HEAVY_FONT)
	gl.add_theme_font_size_override("font_size", 12)
	gl.add_theme_color_override("font_color", Color("#3a1c02"))
	gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gr.add_child(gl)
	gt.reset_size()
	gt.position = Vector2(at.size.x - gt.get_combined_minimum_size().x + 10.0, at.size.y - 5.0)   # (off the words)

static func _tag(parent: Control, text: String, font := 12) -> PanelContainer:
	# a gold tag with dark text (the tutorial's gold in the menu)
	var tag := PanelContainer.new()
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color("#ffc94d")
	ts.border_color = Color("#3a1c02")
	ts.set_border_width_all(2)
	ts.set_corner_radius_all(10)
	ts.content_margin_left = 8
	ts.content_margin_right = 8
	ts.content_margin_top = 1
	ts.content_margin_bottom = 1
	ts.shadow_color = Color(0, 0, 0, 0.35)
	ts.shadow_size = 4
	tag.add_theme_stylebox_override("panel", ts)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(tag)
	var tl := Label.new()                          # (not UI.label: a wrapping label sizes the tag a letter wide first)
	tl.text = text
	tl.add_theme_font_override("font", UI.HEAVY_FONT)
	tl.add_theme_font_size_override("font_size", font)
	tl.add_theme_color_override("font_color", Color("#3a1c02"))
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_child(tl)
	var tw := (UI.HEAVY_FONT as Font).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font).x + 22.0
	tag.custom_minimum_size = Vector2(tw, 22)
	tag.size = tag.custom_minimum_size
	return tag

static func _online_pill(app, top: Control, at: Rect2, centred: bool) -> void:
	# --- players online (0.31.82, Kevin: "Add a players online in main menu"), painted by app.paint_online() from the
	# server's status answer (FATEBOUND / 5 vs 5 until one comes). 0.31.194: B2's green pill with a gold rim -- crossed
	# swords, the line and the live dot -- on the top row's left (in the middle once JOIN OUR DISCORD has gone)
	var pill := Control.new()
	pill.name = "OnlinePill"
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(pill)
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 7)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(r)
	var sw := UI2.icon(r, "swords", 28.0)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -3)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(col)
	var om := UI2.text(col, "FATEBOUND", 14, Color.WHITE, Color("#0b2a14"), 5)
	om.clip_text = true
	var osub := UI2.text(col, "5 vs 5", 11, Color("#d9ffcf"), Color("#0b2a14"), 4)
	var dot := Panel.new()                                # the live dot breathes
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color("#b9ff7a")
	ds.set_corner_radius_all(4)
	ds.shadow_color = Color(0.7, 1.0, 0.4, 0.7)
	ds.shadow_size = 4
	dot.add_theme_stylebox_override("panel", ds)
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(dot)
	UI2.when_ready(dot, func():
		var tw := dot.create_tween().set_loops()
		tw.tween_property(dot, "modulate:a", 0.3, 0.8).set_trans(Tween.TRANS_SINE)
		tw.tween_property(dot, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE))
	# (as wide as its longest line can be -- "12 PLAYERS ONLINE" -- up to the room there is)
	var tw := (UI2.LG as Font).get_string_size("123 PLAYERS ONLINE", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 10.0 + 28.0 + 8.0 + 14.0 + 20.0
	var pw := minf(at.size.x, tw)
	pill.size = Vector2(pw, at.size.y)
	pill.position = Vector2(at.position.x + ((at.size.x - pw) * 0.5 if centred else 0.0), at.position.y)
	r.position = Vector2(10, 0)
	r.size = Vector2(pw - 20, at.size.y)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI2.plate(pill, "green", at.size.y * 0.5, "gold", {"rim": 2.5, "shadow_y": 3.0})
	app.online_refs = {"main": om, "sub": osub}
	if app.has_method("paint_online"):
		app.paint_online()

# ---------- chests (0.31.37; 0.31.79 in 3D; 0.31.194 on B2's panels) ----------
static func chests_row(app, parent: Control, w: float, y: float) -> void:
	# each slot a dark wood panel: the chest's name on top, the chest in 3D in the middle (all four in one view, over the
	# panels), and under it what you can do -- OPEN, the time left and SKIP for gems, UNLOCK, or how long it'll take once
	# it's its turn (QUEUED); an empty one shows a dim chest to come
	var p = app.profile
	var busy: Dictionary = p.unlocking()
	var gap := 8.0
	var sw := (w - gap * 3.0) / 4.0
	var sh := CHEST_H
	var slots := []
	for i in Eco.CHEST_SLOTS:                           # the panels (under the chests)
		var x := i * (sw + gap)
		var plate := Control.new()
		plate.position = Vector2(x, y)
		plate.size = Vector2(sw, sh)
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.set_meta("chest_plate", i)                # (0.31.198: the Herald's tour shows the row)
		parent.add_child(plate)
		if i >= p.chests().size():
			UI2.plate(plate, "glass", 12.0, "brown", {"fill_top": Color(CHEST_FILL[0], 0.55), "fill_bottom": Color(CHEST_FILL[1], 0.7),
				"outline_color": Color(0.85, 0.62, 0.32, 0.5)})
			continue
		var ch: Dictionary = p.chests()[i]
		var k := str(ch.kind)
		var ready: bool = p.chest_ready(ch)
		if ready:
			UI2.glow(plate, Rect2(-14, -14, sw + 28, sh + 28), Color(0.55, 1.0, 0.6, 0.5))
		UI2.plate(plate, "night", 12.0, "green" if ready else "brown", {"fill_top": CHEST_FILL[0], "fill_bottom": CHEST_FILL[1]})
		slots.append({"kind": k, "mode": "tease" if ready else "idle", "x": x + sw * 0.5})
	var row := ChestRow.new()                           # the chests themselves, in 3D
	row.slots = slots
	row.position = Vector2(0, y + 12.0)
	row.size = Vector2(w, 66.0)
	row.chest_px = minf(66.0, sw - 12.0)
	row.base_y = 0.9
	parent.add_child(row)
	var waiting: int = p.chests_waiting()
	if waiting > 0:                                     # 0.31.108: reward chests waiting for a free slot (over the row)
		var wc := UI2.chip(parent, "+%d WAITING" % waiting, Color(0.03, 0.02, 0.1, 0.92), UI2.GOLD, Color(UI2.GOLD, 0.8))
		wc.position = Vector2(w - 108, y - 26)
		wc.set_meta("action_key", "chests_waiting")
	for i in Eco.CHEST_SLOTS:                           # and what's on each panel (over the chests)
		var x := i * (sw + gap)
		var cell := Control.new()
		cell.position = Vector2(x, y)
		cell.size = Vector2(sw, sh)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(cell)
		if i >= p.chests().size():
			var ghost := UI2.img(cell, UI2.V2 + "chests/wood_icon.png", 48.0)
			ghost.position = Vector2((sw - 48.0) * 0.5, 20.0)
			ghost.modulate = Color(0.85, 0.75, 0.62, 0.45)           # (a dim silhouette of the chest to come)
			ghost.set_meta("empty_slot", true)
			var first_empty: bool = i == p.chests().size()
			var e := UI2.text(cell, "WIN TO EARN" if first_empty else "EMPTY", 11, Color(1.0, 0.93, 0.8, 0.85) if first_empty else Color(0.9, 0.82, 0.7, 0.55), UI2.INK, 3)
			e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			e.position = Vector2(0, sh - 26)
			e.size = Vector2(sw, 16)
			e.mouse_filter = Control.MOUSE_FILTER_IGNORE
			continue
		var ch: Dictionary = p.chests()[i]
		var k := str(ch.kind)
		var ready: bool = p.chest_ready(ch)
		var idx := i
		_chest_name(cell, k, sw, Color("#c9ffb8") if ready else UI2.CREAM)
		if ready:
			var ob := UI2.button(cell, "OPEN", "green", func(): open_chest(app, idx), "chest_open_%d" % i, 15, 28.0, 9.0)
			ob.position = Vector2(6, sh - 33)
			ob.size = Vector2(sw - 12, 28)
			UI2.sweep(ob, 2.2, 30.0, 0.6)
		elif int(ch.start) >= 0:
			_slot_tag(cell, UI.duration(p.chest_left(ch)), UI2.GOLD)
			var frac := 1.0 - float(p.chest_left(ch)) / float(Eco.CHESTS[k].unlock)
			var pb := UI2.bar(cell, frac, 1.0, Color("#fff1a6"), Color("#f0a024"), 6.0)
			pb.position = Vector2(8, sh - 40)
			pb.size = Vector2(sw - 16, 6)
			var sb := UI2.button(cell, "%d" % Eco.skip_cost(p.chest_left(ch)), "purple", func(): skip_chest(app, idx), "chest_skip_%d" % i, 14, 28.0, 9.0, "res://assets/ui/currency/gem.png")
			sb.position = Vector2(6, sh - 33)
			sb.size = Vector2(sw - 12, 28)
		elif busy.is_empty():
			_slot_tag(cell, UI.duration(p.chest_left(ch)), Color.WHITE)
			var ub := UI2.button(cell, "UNLOCK", "blue", func():
				p.start_unlock(idx)
				app.sfx("unlock")                  # 0.31.110: a key turns, ka-chunk
				app.rebuild()
				if app.has_method("chest_started"):
					app.chest_started(), "chest_unlock_%d" % i, 13, 28.0, 9.0)
			ub.position = Vector2(6, sh - 33)
			ub.size = Vector2(sw - 12, 28)
		else:
			# waiting its turn: how long it'll take, under a dark QUEUED pill (B2's); tapping it opens it now for gems
			var q := PanelContainer.new()
			var qs := StyleBoxFlat.new()
			qs.bg_color = Color(0.0, 0.0, 0.0, 0.45)
			qs.border_color = Color(0.85, 0.62, 0.32, 0.45)
			qs.set_border_width_all(1)
			qs.set_corner_radius_all(9)
			q.add_theme_stylebox_override("panel", qs)
			q.position = Vector2(6, sh - 33)
			q.size = Vector2(sw - 12, 28)
			q.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(q)
			var tr := HBoxContainer.new()
			tr.alignment = BoxContainer.ALIGNMENT_CENTER
			tr.add_theme_constant_override("separation", 3)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			q.add_child(tr)
			UI2.icon(tr, "hourglass", 18.0)
			UI2.text(tr, UI.duration(p.chest_left(ch)), 14, Color.WHITE, Color("#1a0d04"), 4)
			_slot_tag(cell, "QUEUED", UI2.MUTED)
			var skip := UI2.button(cell, "", "ghost", func(): skip_chest(app, idx), "chest_skip_%d" % i, 10, 20.0, 8.0)
			skip.position = Vector2(4, 18)
			skip.size = Vector2(sw - 8, sh - 22)
			skip.modulate = Color(1, 1, 1, 0)            # (unseen: its skin too -- self_modulate left that over the chest)

static func _chest_name(cell: Control, kind: String, sw: float, col: Color) -> void:
	# the chest's name along the top of its panel ("SILVER CHEST"; just "SILVER" where the whole name won't fit)
	var n := str(Eco.CHESTS[kind].name).to_upper()
	if (UI2.LG as Font).get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x > sw - 8.0:
		n = n.get_slice(" ", 0)
	var l := UI2.text(cell, n, 10, col, UI2.INK, 3)
	l.name = "ChestName"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(0, 4)
	l.size = Vector2(sw, 14)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE

static func _slot_tag(cell: Control, s: String, col: Color) -> void:
	# the time on a chest (or QUEUED), a chip over the chest's foot
	var c := UI2.chip(cell, s, Color(0.01, 0.02, 0.08, 0.85), col, Color(col, 0.7))
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.offset_left = -30
	c.offset_right = 30
	c.offset_top = 46
	c.offset_bottom = 62

static func skip_chest(app, idx: int) -> void:
	var r: Dictionary = app.profile.skip_chest(idx)
	if bool(r.get("ok", false)):
		open_chest(app, idx)                   # (its sound: the chest's window opening)
	else:
		app.sfx("error")
		app.toast("Not enough gems (%d needed)" % int(r.get("cost", 0)), UI.RED)

static func open_chest(app, idx: int) -> void:
	# 0.31.79: the 3D opening (chest_open.gd); the roll happens when the chest is tapped open.
	var chs: Array = app.profile.chests()
	if idx < 0 or idx >= chs.size() or not app.profile.chest_ready(chs[idx]):
		return
	app.sfx("menuOpen")
	app.close_modal()
	var m := ChestOpen.new()
	m.app = app
	m.index = idx
	m.kind = str(chs[idx].kind)
	app.add_child(m)
	app.modal = m

static func chest_odds(app) -> void:
	var lines := []
	for k in ["wooden", "silver", "gold", "royal"]:
		lines.append("%s (%s): %s" % [str(Eco.CHESTS[k].name), UI.duration(int(Eco.CHESTS[k].unlock)), Eco.chest_odds(k)])
	app.toast("\n".join(lines), UI.TEXT)

static func challenges_card(app, root: Node, span: String) -> Control:
	# 0.31.79: the orders on a parchment sheet
	var p = app.profile
	var list: Array = p.d.challenges.daily if span == "daily" else p.d.challenges.weekly
	var c := UI2.frame(root, "parch", 12, 14.0, "brown")
	var now: int = p.now()
	var reset: int = (int(floor(now / 86400.0)) + 1) * 86400 - now if span == "daily" else 0
	if span == "weekly":
		var days := int(floor(now / 86400.0))
		var monday := days - ((days + 3) % 7)
		reset = (monday + 7) * 86400 - now
	var ink := Color("#3b2412")
	var h := UI.row(c, 8)
	UI2.icon(h, "scroll" if span == "daily" else "hourglass", 30.0)
	UI.grow(UI2.text(h, "DAILY ORDERS" if span == "daily" else "WEEKLY ORDERS", 19, ink, ink, 0, false))
	var rl := UI.label(h, "resets in " + UI.duration(reset), 11, Color("#7a5530"), UI.HEAVY_FONT)
	rl.autowrap_mode = TextServer.AUTOWRAP_OFF
	for i in list.size():
		var ch: Dictionary = list[i]
		if not Eco.CHALLENGES.has(str(ch.id)):
			continue                                   # (0.31.164: a retired Siege one, before the profile swapped it)
		var def: Dictionary = Eco.CHALLENGES[ch.id]
		var row := UI.row(c, 10)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 3)
		UI.grow(v)
		row.add_child(v)
		UI.label(v, str(def.text), 13, ink, UI.HEAVY_FONT)
		var reward := "+%d pass XP" % int(def.pass)
		var order_gold := int(def.get("gold", 0)) + (Eco.DAILY_GOLD if span == "daily" else 0)     # (0.31.184: a daily's Embers are gold)
		if order_gold > 0:
			reward += " · +%d gold" % order_gold
		if def.has("gems"):
			reward += " · +%d gems" % int(def.gems)
		var pr := UI.row(v, 6)
		UI2.bar(pr, int(ch.progress), int(def.goal), Color("#a8e4ff") if not bool(ch.claimed) else Color("#b4f7a4"), Color("#2b8fd6") if not bool(ch.claimed) else Color("#25a248"), 10.0)
		UI.label(pr, "%d/%d" % [mini(int(ch.progress), int(def.goal)), int(def.goal)], 11, ink, UI.HEAVY_FONT).autowrap_mode = TextServer.AUTOWRAP_OFF
		UI.label(v, reward, 11, Color("#8a5a0a"), UI.HEAVY_FONT)
		var done: bool = int(ch.progress) >= int(def.goal)
		if bool(ch.claimed):
			UI.icon(row, "check", 28, Color("#2f8a4f"))
		elif done:
			var cb := UI2.button(row, "CLAIM", "green", func():
				var r: Dictionary = p.claim_challenge(span, i)
				if r.ok:
					app.sfx("claim")
					app.toast("Order complete!" + (" Pass tier %d reached" % int(r.tiers[-1]) if not r.tiers.is_empty() else ""), UI.GREEN)
				app.rebuild(), "claim_%s_%d" % [span, i], 15, 38.0, 10.0)
			cb.custom_minimum_size.x = 84
			UI2.sweep(cb, 2.2, 30.0)
		elif span == "daily" and not bool(p.d.challenges.rerolled):
			var rb := UI2.button(row, "↻", "blue", func():
				if p.reroll_daily(i):
					app.sfx("flip")
				app.rebuild(), "reroll_%d" % i, 18, 36.0, 10.0)
			rb.custom_minimum_size.x = 40
			rb.add_theme_font_override("font", UI.HEAVY_FONT)
	return c.get_parent()

static func pass_card(app, root: Node) -> void:
	# Home's Siege Pass summary: the tier medallion, the XP bar and CLAIM / VIEW.
	var p = app.profile
	var d: Dictionary = p.d
	var pc := UI2.frame(root, "purple", 12, 18.0, "gold")
	var tier: int = p.pass_tier()
	var r := UI.row(pc, 12)
	var med := Control.new()
	med.custom_minimum_size = Vector2(58, 66)
	r.add_child(med)
	var mt := TextureRect.new()
	mt.texture = UI2.tex(UI2.V2 + "shield_pass.svg")
	mt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	med.add_child(mt)
	var tn := UI2.text(med, str(tier), 26, Color.WHITE, Color("#1e0a45"), 6)
	tn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tn.offset_bottom = -8
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	UI.grow(v)
	r.add_child(v)
	UI2.text(v, "SIEGE PASS", 20, UI2.GOLD, UI2.INK, 5)
	var ends: int = Eco.season_ends(int(d.pass.season)) - p.now()
	UI2.body(v, "%s  ·  %s left" % [Eco.season_name(int(d.pass.season)), UI.duration(ends)], 11, Color("#e6d6ff"), false)
	var in_tier: int = int(d.pass.xp) - tier * Eco.TIER_XP
	UI2.bar(v, in_tier if tier < Eco.PASS_TIERS else 1, Eco.TIER_XP if tier < Eco.PASS_TIERS else 1, Color("#fff3a8"), Color("#e08a12"), 12.0)
	var claimable := 0
	for t in range(1, tier + 1):
		for prem in [false, true]:
			if p.can_claim(t, prem):
				claimable += 1
	var b := UI2.button(pc, ("CLAIM %d REWARD%s" % [claimable, "" if claimable == 1 else "S"]) if claimable > 0 else "VIEW PASS", "green" if claimable > 0 else "blue", func(): app.show_tab("pass"), "go_pass", 18, 46.0)
	if claimable > 0:
		UI2.sweep(b)

# ---------------- PASS ----------------
static func banner(root: Node, art: String, title: String, h := 210.0, title_color := UI2.GOLD) -> Control:
	# 0.31.79: a gold-framed painted banner at the top of a tab, its title over the bottom of the art.
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(c)
	var clip := Control.new()
	clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(clip)
	var t := TextureRect.new()
	t.texture = UI2.tex(art)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(t)
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.03, 0.02, 0.1, 0.0))
	g.set_color(1, Color(0.03, 0.02, 0.1, 0.85))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.5, 0.35)
	gt.fill_to = Vector2(0.5, 1.0)
	gt.width = 4
	gt.height = 64
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(shade)
	# the frame: rim and outline only, over the art
	UI2.plate(c, "royal", 20.0, "gold", {"fill_top": Color(0, 0, 0, 0), "fill_bottom": Color(0, 0, 0, 0), "pattern_mix": 0.0, "rim": 4.0, "bevel": 0.0})
	(c.get_child(0) as Node2D).show_behind_parent = false
	c.move_child(c.get_child(0), c.get_child_count() - 1)
	clip.offset_left = 4
	clip.offset_top = 4
	clip.offset_right = -4
	clip.offset_bottom = -4
	var tl := UI2.text(c, title, 40, title_color, UI2.INK, 10)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	tl.offset_top = -78
	tl.offset_bottom = -30
	for i in 3:
		var sp := UI2.glow(c, Rect2(randf_range(20, 360), randf_range(20, h - 90), 12, 12), Color(1, 0.95, 0.8, 0.9))
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func pass_screen(app, root: VBoxContainer) -> void:
	# 0.31.42 (Kevin): a richer Siege Pass; 0.31.79: the painted banner, the tier medallion in a sunburst, the premium
	# offer, then the track -- free on the left, premium on the right, a gold spine. (0.31.79-0.31.187: the season's best
	# weapon turning in 3D under the offer -- 0.31.188 the pass gives no cosmetics: outfits are bought.)
	var p = app.profile
	var d: Dictionary = p.d
	var sid: int = int(d.pass.season)
	var tier: int = p.pass_tier()

	# --- banner
	var ban := banner(root, UI2.V2 + "art_pass.webp", "SIEGE PASS", 214.0)
	var rib := UI2.ribbon(ban, "SEASON %d  ·  %s" % [sid, str(Eco.season_name(sid)).to_upper()], "", 300.0, 30.0, [Color("#b37bff"), Color("#4a1a96")])
	rib.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	ban.resized.connect(func(): rib.position = Vector2((ban.size.x - 300.0) * 0.5, ban.size.y - 34.0))
	var ends := UI2.icon_chip(ban, UI2.icon_path("hourglass"), "ENDS IN %s" % UI.duration(Eco.season_ends(sid) - p.now()).to_upper(), Color(0.03, 0.02, 0.1, 0.82), UI2.GOLD, Color(UI2.GOLD, 0.7))
	ends.position = Vector2(12, 12)

	# --- tier card
	var tc := UI2.frame(root, "royal", 12, 18.0, "gold")
	var tr := UI.row(tc, 12)
	var med := Control.new()
	med.custom_minimum_size = Vector2(72, 82)
	tr.add_child(med)
	var mr := UI2.rays(med, 150.0, Color(1, 0.86, 0.45), 16.0, 0.6)
	mr.position = Vector2(-39, -34)
	var mt := TextureRect.new()
	mt.texture = UI2.tex(UI2.V2 + "shield_pass.svg")
	mt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	med.add_child(mt)
	var tn := UI2.text(med, str(tier), 32, Color.WHITE, Color("#1e0a45"), 7)
	tn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tn.offset_bottom = -10
	var xv := VBoxContainer.new()
	xv.add_theme_constant_override("separation", 5)
	xv.alignment = BoxContainer.ALIGNMENT_CENTER
	UI.grow(xv)
	tr.add_child(xv)
	var hr := UI.row(xv, 6)
	UI.grow(UI2.text(hr, "TIER %d" % tier, 24, Color.WHITE))
	if tier < Eco.PASS_TIERS:
		UI2.body(hr, "NEXT: TIER %d" % (tier + 1), 11, UI2.SOFT, false)
		var xp_in: int = int(d.pass.xp) - tier * Eco.TIER_XP
		var bh := UI2.bar(xv, xp_in, Eco.TIER_XP, Color("#fff3a8"), Color("#e08a12"), 18.0)
		var xl := UI2.body(bh, "%d / %d XP" % [xp_in, Eco.TIER_XP], 11, Color.WHITE, false)
		xl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		xl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		xl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		xl.add_theme_constant_override("outline_size", 3)
	else:
		UI2.text(xv, "PASS COMPLETE", 18, UI2.GOLD)
	UI2.body(xv, "Earn pass XP from every match and order", 11, UI2.MUTED)

	# --- tier skip (0.31.107)
	var so: Dictionary = p.skip_offer()
	if int(so.tiers) > 0:
		var kc := UI2.frame(root, "night", 10, 16.0, "gold")
		var kr := UI.row(kc, 10)
		var ki := UI2.img(kr, "res://assets/ui/v2/shield_pass.svg", 46.0)
		var kn := UI2.text(ki, "+%d" % int(so.tiers), 16, Color.WHITE, Color("#1e0a45"), 5)
		kn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		kn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		kn.offset_top = 9
		UI2.wiggle(ki, 4.0)
		var kv := VBoxContainer.new()
		kv.add_theme_constant_override("separation", 1)
		UI.grow(kv)
		kr.add_child(kv)
		UI2.text(kv, "SKIP %d TIER%s" % [int(so.tiers), "" if int(so.tiers) == 1 else "S"], 18, UI2.GOLD)
		UI2.body(kv, "Jump to tier %d  ·  claim every reward on the way" % (tier + int(so.tiers)), 11, Color("#dfe6ff"))
		var kb := UI2.button(kr, str(int(so.gems)), "purple", func(): _skip_tiers(app), "skip_tiers", 17, 44.0, 12.0, "res://assets/ui/currency/gem.png")
		kb.custom_minimum_size.x = 112
		kb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		kb.disabled = int(d.gems) < int(so.gems)

	# --- premium
	if bool(d.pass.premium):
		var pa := UI2.frame(root, "purple", 10, 16.0, "gold")
		var pr := UI.row(pa, 10)
		UI2.icon(pr, "crown", 40.0)
		UI.grow(UI2.body(pr, "PREMIUM ACTIVE -- all %d premium rewards are yours to claim" % Eco.PASS_TIERS, 13, Color("#f3e6ff")))
	else:
		var pc := UI2.frame(root, "purple", 12, 18.0, "purple")
		var ph := UI.row(pc, 10)
		var cr := UI2.icon(ph, "crown", 52.0)
		UI2.wiggle(cr, 3.2)
		var pt := VBoxContainer.new()
		pt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ph.add_child(pt)
		UI2.text(pt, "UNLOCK PREMIUM", 20, UI2.GOLD)
		UI2.body(pt, premium_summary(sid), 12, Color("#efe2ff"))
		var b := UI2.button(pc, "UNLOCK  %d" % Eco.PREMIUM_COST, "purple", func(): _buy_premium(app), "buy_premium", 20, 52.0, 16.0, "res://assets/ui/currency/gem.png")
		b.disabled = int(d.gems) < Eco.PREMIUM_COST
		UI2.sweep(b)
		UI2.center(UI2.body(pc, "You have %d gems" % int(d.gems), 11, Color("#d8c6ff")))

	# --- claim all
	var claimable := 0
	for t in range(1, tier + 1):
		for prem in [false, true]:
			if p.can_claim(t, prem):
				claimable += 1
	if claimable > 0:
		var ca := UI2.button(root, "CLAIM ALL  (%d)" % claimable, "green", func():
			var got: Array = p.claim_all()
			app.sfx("claim")
			app.toast("Claimed %d reward%s" % [got.size(), "" if got.size() == 1 else "s"], UI.GREEN)
			app.rebuild(), "claim_all", 24, 58.0, 18.0)
		UI2.sweep(ca)
		UI2.pulse(ca, 0.02)

	# --- the track
	var head := UI.row(root, 0)
	for side in [false, true]:
		if side:
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(50, 0)
			head.add_child(gap)
		var hp := PanelContainer.new()
		var hs := StyleBoxEmpty.new()
		hs.content_margin_top = 5
		hs.content_margin_bottom = 3
		hp.add_theme_stylebox_override("panel", hs)
		hp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(hp)
		UI2.skin(hp, UI2.button_params("purple" if side else "blue", 12.0, 4.0))
		var hl := UI2.text(hp, "PREMIUM" if side else "FREE", 16, Color.WHITE, Color("#1e0a45") if side else Color("#0a1238"), 4)
		hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for t in range(1, Eco.PASS_TIERS + 1):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		root.add_child(row)
		pass_cell(app, row, sid, t, false)
		_spine(row, t, tier)
		pass_cell(app, row, sid, t, true)

static func premium_summary(sid: int) -> String:
	# what the premium track holds, counted from the season's rewards: "A Hero Token (any hero) · 3 hero shards · ..."
	var n := {"token": 0, "shard": 0, "royal": 0, "gold": 0, "gems": 0}
	for t in range(1, Eco.PASS_TIERS + 1):
		var r := Eco.pass_reward(sid, t, true)
		n.token += int(r.get("token", 0))
		n.shard += 1 if r.has("shard") else 0
		n.gems += int(r.get("gems", 0))
		if r.has("chest"):
			n[str(r.chest) if str(r.chest) in ["royal", "gold"] else "gold"] += 1
	var bits := []
	if int(n.token) > 0:
		bits.append("A Hero Token (any hero)")
	if int(n.shard) > 0:
		bits.append("%d hero shards" % int(n.shard))
	bits.append("%d Royal and %d Gold chests" % [int(n.royal), int(n.gold)])
	if int(n.gems) > 0:
		bits.append("%s gems" % UI.grouped(int(n.gems)))
	bits.append("more gold on every tier")
	return " · ".join(bits)

const PASS_GOLD := Color("#ffcf5a")
const PASS_PURPLE := Color("#b77cff")

static func _panel(parent: Node, fill: Color, edge: Color, radius: int, glow: Color, pad: int) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = edge
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = glow
	sb.shadow_size = 10
	for side in ["left", "right", "top", "bottom"]:
		sb.set("content_margin_" + side, float(pad))
	pc.add_theme_stylebox_override("panel", sb)
	parent.add_child(pc)
	return pc

static func _chip(parent: Node, text: String, fill: Color, ink: Color) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	pc.add_theme_stylebox_override("panel", sb)
	pc.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(pc)
	var l := UI.label(pc, text, 10, ink, UI.HEAVY_FONT)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return pc

static func _spine(row: Node, t: int, tier: int) -> void:
	# the centre column: a gold line through the reached tiers, the tier number in a medal
	var col := Control.new()
	col.custom_minimum_size = Vector2(44, 0)
	row.add_child(col)
	var reached := t <= tier
	var line_top := ColorRect.new()
	var line_bot := ColorRect.new()
	for ln in [line_top, line_bot]:
		(ln as ColorRect).mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(ln)
	line_top.color = PASS_GOLD if reached else Color(1, 1, 1, 0.1)
	line_bot.color = PASS_GOLD if t < tier else Color(1, 1, 1, 0.1)
	var m := Control.new()
	m.size = Vector2(40, 40) if t != tier else Vector2(46, 46)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(m)
	if reached:
		UI2.plate(m, "royal", 23.0, "gold", {"fill_top": Color("#fff2b0"), "fill_bottom": Color("#d98516"), "pattern_mix": 0.0, "rim": 0.0, "outline": 2.5,
			"glow": 8.0 if t == tier else 0.0, "glow_color": Color(1.0, 0.84, 0.35, 0.8), "shadow_y": 3.0})
	else:
		UI2.plate(m, "night", 20.0, "gold", {"rim": 0.0, "outline": 2.0, "outline_color": Color(1, 0.84, 0.35, 0.35), "shadow_y": 3.0})
	var l := UI2.text(m, str(t), 17 if t != tier else 20, Color("#3a1c02") if reached else Color("#c8bfe8"), Color("#fff1b8") if reached else Color("#0b0620"), 0 if reached else 3, false)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.offset_top = 2
	col.resized.connect(func():
		var cx := col.size.x * 0.5
		line_top.position = Vector2(cx - 3, 0)
		line_top.size = Vector2(6, col.size.y * 0.5)
		line_bot.position = Vector2(cx - 3, col.size.y * 0.5)
		line_bot.size = Vector2(6, col.size.y * 0.5 + 8)
		m.position = Vector2(cx, col.size.y * 0.5) - m.size * 0.5)
	if t == tier and is_instance_valid(m):
		UI2.pulse(m, 0.08, 0.8)

static func pass_cell(app, parent: Node, sid: int, t: int, prem: bool) -> void:
	var p = app.profile
	var r: Dictionary = p.pass_reward_for(t, prem)          # (a shard: the hero it is for this player)
	var rt: Array = reward_text(r)
	var claimed: bool = (p.d.pass.prem if prem else p.d.pass.free).has(t)
	var ready: bool = p.can_claim(t, prem)
	var locked_prem: bool = prem and not bool(p.d.pass.premium)
	var locked: bool = t > p.pass_tier()
	var kind := "purple" if prem else "royal"
	var rim := "purple" if prem else "gold"
	if ready:
		kind = "green"
		rim = "green"
	var cell := Control.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.custom_minimum_size = Vector2(0, 116 if ready else 104)
	parent.add_child(cell)
	if ready:
		var g := UI2.glow(cell, Rect2(-16, -16, 10, 10), Color(0.55, 1.0, 0.6, 0.5))
		cell.resized.connect(func(): g.size = cell.size + Vector2(32, 32))
	UI2.plate(cell, kind, 16.0, rim, {"dim": 0.45 if (claimed or locked_prem) else 0.0})
	if r.has("chest") and str(r.chest) == "royal" and not claimed:
		var rays := UI2.rays(cell, 150.0, Color(0.85, 0.6, 1.0), 20.0, 0.35)       # (a Royal chest stands out)
		cell.resized.connect(func(): rays.position = Vector2(cell.size.x * 0.5 - 75.0, 4.0))
		cell.clip_contents = false
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_top = 6
	v.offset_bottom = -30 if ready else -6
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(v)
	var ic := CenterContainer.new()
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ic)
	if r.has("chest"):
		var ci := UI2.img(ic, chest_icon(str(r.chest)), 58.0)
		if ready:
			UI2.bob(ci, 3.0, 0.9)
	elif str(rt[3]) != "":
		var ti := UI2.img(ic, str(rt[3]), 54.0)
		if ready:
			UI2.bob(ti, 3.0, 0.9)
	else:
		UI.icon(ic, str(rt[0]), 34, rt[2])
	var nm := UI2.text(v, str(rt[1]).to_upper(), 13, Color.WHITE, UI2.INK, 4, false)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if claimed or locked or locked_prem:
		var badge := Control.new()
		badge.size = Vector2(28, 28)
		badge.position = Vector2(-4, -4)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(badge)
		if claimed:
			UI2.plate(badge, "green", 14.0, "green", {"rim": 0.0, "fill_top": Color("#8ff09a"), "fill_bottom": Color("#27a248"), "pattern_mix": 0.0})
			var ck := UI.icon(badge, "check", 18, Color.WHITE)
			ck.position = Vector2(5, 5)
		else:
			UI2.plate(badge, "night", 14.0, "gold", {"rim": 0.0, "outline": 2.0, "outline_color": PASS_PURPLE if locked_prem else Color(1, 1, 1, 0.3)})
			var lk := UI.icon(badge, "lock", 16, PASS_PURPLE if locked_prem else UI.MUTED)
			lk.position = Vector2(6, 5)
	var tap := Button.new()
	tap.flat = true
	for st_name in ["normal", "hover", "pressed", "focus"]:
		tap.add_theme_stylebox_override(st_name, StyleBoxEmpty.new())
	tap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tap.pressed.connect(func(): open_pass_item(app, sid, t, prem))
	cell.add_child(tap)
	if ready:
		var gb := UI2.button(cell, "CLAIM", "green", func(): _claim_tier(app, t, prem), "claim_%s_%d" % ["prem" if prem else "free", t], 14, 28.0, 9.0)
		gb.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		gb.offset_top = -36
		gb.offset_bottom = -7
		gb.offset_left = 10
		gb.offset_right = -10
		UI2.sweep(gb, 2.0, 30.0)

static func _claim_tier(app, t: int, prem: bool) -> void:
	var res: Dictionary = app.profile.claim_tier(t, prem)
	if res.ok:
		app.sfx("claim")
		var got: Array = reward_text(res.reward)
		app.toast("+ " + str(got[1]), UI.GREEN)
	app.close_modal()
	app.rebuild()

static func _skip_tiers(app) -> void:
	var p = app.profile
	var so: Dictionary = p.skip_offer()
	var to: int = p.pass_tier() + int(so.tiers)
	app.confirm("SKIP %d TIERS?" % int(so.tiers), "Jump straight to tier %d of the Siege Pass. Costs %d gems." % [to, int(so.gems)], "SKIP", "premium", func():
		var r: Dictionary = p.skip_tiers()
		if r.ok:
			app.sfx("tierUp")                  # 0.31.110: a bright rising chime
			app.toast("Tier %d reached! Claim your rewards" % p.pass_tier(), UI.GOLD)
		else:
			app.sfx("error")
			app.toast(str(r.error), UI.RED)
		app.rebuild())

static func _buy_premium(app) -> void:
	var p = app.profile
	var psid := int(app.profile.d.pass.season)
	app.confirm("UNLOCK PREMIUM?", "%s this season. Costs %d gems." % [premium_summary(psid), Eco.PREMIUM_COST], "UNLOCK", "premium", func():
		var r: Dictionary = p.buy_premium()
		if r.ok:
			app.sfx("premium")                 # 0.31.110: a rich golden chord
			app.toast("Premium pass unlocked!", UI.PURPLE)
		else:
			app.sfx("error")
			app.toast(str(r.error), UI.RED)
		app.rebuild())

static func open_pass_item(app, sid: int, t: int, prem: bool) -> void:
	# the detail view: the reward big (0.31.42-0.31.187: a weapon in its class's hands, turning with your finger)
	var p = app.profile
	var r: Dictionary = p.pass_reward_for(t, prem)
	var rt: Array = reward_text(r)
	app.sfx("menuOpen")
	app.close_modal()
	var m := Control.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.add_child(m)
	app.modal = m
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.05, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	margin.add_theme_constant_override("margin_top", 60)
	margin.add_theme_constant_override("margin_bottom", 40)
	m.add_child(margin)
	var edge: Color = PASS_PURPLE if prem else PASS_GOLD
	var sheet := _panel(margin, Color("#140d26"), edge, 22, Color(edge.r, edge.g, edge.b, 0.45), 14)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	sheet.add_child(v)
	var hr := UI.row(v, 8)
	_chip(hr, ("PREMIUM" if prem else "FREE") + "  ·  TIER %d" % t, PASS_PURPLE if prem else Color("#2b3a55"), Color.WHITE)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hr.add_child(sp)
	UI.button(hr, "✕", "ghost", func():
		app.sfx("menuClose")
		app.close_modal(), "pass_detail_close", 16, 12)
	var stage := Control.new()
	stage.clip_contents = true
	stage.custom_minimum_size = Vector2(0, 340)
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(stage)
	Showcase.backdrop(stage)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(cc)
	var icc := CenterContainer.new()
	cc.add_child(icc)
	if str(rt[3]) != "":
		UI.tex_icon(icc, str(rt[3]), 120)
	else:
		UI.icon(icc, str(rt[0]), 96, rt[2])
	var nm := UI.label(v, str(rt[1]), 24, Color.WHITE, UI.TITLE_FONT, true)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if r.has("chest"):
		var cd := UI.label(v, Eco.chest_odds(str(r.chest)), 11, UI.MUTED)
		cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var claimed: bool = (p.d.pass.prem if prem else p.d.pass.free).has(t)
	if claimed:
		UI.button(v, "CLAIMED ✓", "secondary", func(): pass, "pass_detail_claimed", 15).disabled = true
	elif p.can_claim(t, prem):
		UI.button(v, "CLAIM", "claim", func(): _claim_tier(app, t, prem), "pass_detail_claim", 16)
	elif prem and not bool(p.d.pass.premium):
		UI.button(v, "UNLOCK PREMIUM  ·  %d GEMS" % Eco.PREMIUM_COST, "premium", func():
			app.close_modal()
			_buy_premium(app), "pass_detail_premium", 15)
	else:
		UI.button(v, "REACH TIER %d TO UNLOCK" % t, "secondary", func(): pass, "pass_detail_locked", 14).disabled = true

# ---------------- SHOP ----------------
static func shop(app, root: VBoxContainer) -> void:
	# 0.31.79: the market stall banner, the week's featured, the daily deals, the Arsenals and the gems. 0.31.188 (Kevin:
	# "I only want the cosmetics to be an entire outfit"): the outfits -- this week's three big (the hero in it, in his
	# own place), then every outfit by hero -- and the gems; tap an outfit to see it on him in his window.
	# 0.31.202 (Kevin: "Let's spruce up and beautify the shop menu"): gems twinkling over the banner; a bar that jumps to
	# FEATURED / OUTFITS / GEMS; the week's outfit with rays of its rarity behind him; the outfits by role (TANK ... SUPPORT,
	# a coin each that jumps to its row; each role's sets on top, its Frostbound line under) on new cards -- his own place
	# painted behind him (frosted for the Frostbound line), a glow of the rarity, OWNED / WORN; the starter pack shining.
	var p = app.profile
	var now: int = p.now()
	var ban := banner(root, UI2.V2 + "art_shop.webp", "MARKET", 196.0)
	var note := UI2.chip(ban, "EVERYTHING HERE IS COSMETIC", Color(0.03, 0.02, 0.1, 0.8), UI2.CREAM, Color(UI2.GOLD, 0.6))
	note.position = Vector2(12, 12)
	_twinkles(ban, 9, Color(0.75, 0.9, 1.0), Rect2(0.12, 0.12, 0.8, 0.5))
	UI2.sweep(ban, 5.0, 90.0, 0.28)
	# 0.31.204 (Kevin: "put a hero tab in the market that shows heroes that player doesn't own and that's where they will
	# purchase them"): the Market in three tabs -- OUTFITS (the weekly sale on top, then every outfit; a red SALE tag on
	# it), HEROES (market_heroes: the ones you don't own, to unlock) and GEMS (the packs). (0.31.202-0.31.203 a bar that
	# jumped down one long page: SALE / OUTFITS / GEMS.)
	if not (str(app.shop_tab) in ["outfits", "heroes", "gems"]):
		app.shop_tab = "outfits"
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	root.add_child(tabs)
	var locked := Champions.ORDER.filter(func(h): return not p.owns_hero(str(h))).size()
	for tb in [["outfits", "OUTFITS", UI2.icon_path("helmet")], ["heroes", "HEROES", UI2.icon_path("crown")],
			["gems", "GEMS", "res://assets/ui/currency/gem.png"]]:
		var tid: String = tb[0]
		var on: bool = str(app.shop_tab) == tid
		var b := UI2.button(tabs, str(tb[1]), "gold" if on else "blue", func():
			if str(app.shop_tab) == tid:
				return
			app.sfx("tab")
			app.shop_tab = tid
			app.content_scroll.scroll_vertical = 0
			app.rebuild(), "shop_tab_" + tid, 14, 40.0, 12.0, str(tb[2]))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tag := ""
		if tid == "outfits" and not Eco.featured_outfits(now).is_empty():
			tag = "SALE"
		elif tid == "heroes" and locked > 0:
			tag = str(locked)
		if tag != "":
			var tc := _card_tag(b, tag, Color("#d6372b"), Color("#3a0805"))
			tc.anchor_left = 1.0
			tc.anchor_right = 1.0
			tc.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			tc.offset_right = 4
			tc.offset_left = -30
			tc.offset_top = -7
			tc.offset_bottom = 9
	match str(app.shop_tab):
		"heroes":
			market_heroes(app, root)
		"gems":
			gem_packs(app, root)
			# (0.31.106-0.31.184 "GEMS -> GOLD": five gold packs for gems. 0.31.185, Kevin: "I want the same IAP system as
			# league of legends" -- League never turns its paid currency into the earned one: gold is earned only, gems buy
			# heroes outright)
			var fn := UI2.icon_chip(root, "res://assets/ui/v2/chests/gold_icon.png", "CHESTS ARE EARNED BY PLAYING  ·  NEVER SOLD",
				Color(0.05, 0.04, 0.16, 0.7), Color("#e8d6b0"), Color(UI2.GOLD, 0.35))
			fn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_:
			var feat: Array = Eco.featured_outfits(now)
			if not feat.is_empty():
				_sale_header(app, root, feat, now)
				var sel := clampi(int(app.get_meta("shop_feat", 0)), 0, feat.size() - 1)
				featured_outfit(app, root, str(feat[sel]))
				var thumbs := HBoxContainer.new()
				thumbs.alignment = BoxContainer.ALIGNMENT_CENTER
				thumbs.add_theme_constant_override("separation", 24)      # (0.31.203: room for their sale badges)
				root.add_child(thumbs)
				for i in feat.size():
					_feat_thumb(app, thumbs, str(feat[i]), i, i == sel)
			UI2.divider(root, "OUTFITS", 22, "a whole new look and weapon  ·  his hero comes with it")      # 0.31.186 (0.31.188: whole outfits)
			skin_grid(app, root)

static func _sale_header(app, root: Node, feat: Array, now: int) -> Control:
	# 0.31.203 (Kevin: "make the graphic of the features look very eye catching"): WEEKLY SALE on a red silk ribbon with
	# gold trim (ElevenLabs art), a shine running along it, stars winking round it; under it the time left, ticking, and
	# how deep the sale goes
	var low := view_low(app)
	var hold := Control.new()
	hold.custom_minimum_size = Vector2(0, 92)
	hold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hold)
	var rb := TextureRect.new()
	rb.texture = UI2.tex(SALE + "sale_ribbon.webp")
	rb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rb.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW          # (the shine stays on the silk)
	rb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hold.add_child(rb)
	var tl := UI2.text(rb, "WEEKLY SALE", 30, Color("#fff4cf"), Color("#4a0306"), 7)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tl.offset_bottom = -12
	if not low:
		UI2.sweep(rb, 2.4, 70.0, 0.55)
		_twinkles(hold, 6, Color(1.0, 0.86, 0.45), Rect2(0.04, 0.02, 0.92, 0.9), 20.0)
		UI2.pulse(rb, 0.025, 0.9)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(row)
	var end := Eco.week_start(now) + 7 * 86400
	var tc := UI2.icon_chip(row, UI2.icon_path("hourglass"), "ENDS IN " + _sale_clock(end - now), Color("#7a0c12"), Color("#ffe3c4"),
		Color("#ffcf6a", 0.7))
	var tlbl: Label = tc.get_child(0).get_child(1)
	var tm := Timer.new()                                 # (it ticks)
	tm.wait_time = 1.0
	tm.autostart = true
	tm.timeout.connect(func():
		if is_instance_valid(tlbl):
			tlbl.text = "ENDS IN " + _sale_clock(end - int(app.profile.now())))
	tc.add_child(tm)
	var most := 0
	for id in feat:
		most = maxi(most, Eco.sale_off(str(id), now))
	UI2.chip(row, "UP TO %d%% OFF" % most, Color("#ffcf4a"), Color("#3a1402"), Color("#fff1b0"))
	return hold

static func _sale_clock(left: int) -> String:
	# the sale's time left: 2D 04:13:52, or 04:13:52 on its last day
	left = maxi(0, left)
	var hms := "%02d:%02d:%02d" % [(left / 3600) % 24, (left / 60) % 60, left % 60]
	return ("%dD %s" % [left / 86400, hms]) if left >= 86400 else hms

static func _sale_badge(parent: Control, off: int, px: float, still := false) -> Control:
	# 0.31.203: the weekly sale's red-and-gold starburst (ElevenLabs art) with its discount on it, tilted; it beats
	var b := Control.new()
	b.size = Vector2(px, px)
	b.pivot_offset = b.size * 0.5
	b.rotation = deg_to_rad(-12.0)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(b)
	if px >= 80.0:
		UI2.glow(b, Rect2(-px * 0.3, -px * 0.3, px * 1.6, px * 1.6), Color(1.0, 0.72, 0.2, 0.75))
	var t := TextureRect.new()
	t.texture = UI2.tex(SALE + "sale_badge.webp")
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(t)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", -int(px * 0.07))
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var big := UI2.text(v, "-%d%%" % off, maxi(9, int(px * 0.27)), Color.WHITE, Color("#4a0306"), maxi(3, int(px * 0.05)), px >= 60.0)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if px >= 60.0:
		var ol := UI2.text(v, "OFF", int(px * 0.14), Color("#ffe9a8"), Color("#4a0306"), 3, false)
		ol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not still:
		UI2.when_ready(b, func():
			var tw := b.create_tween().set_loops()
			tw.tween_property(b, "scale", Vector2.ONE * 1.12, 0.12).set_trans(Tween.TRANS_SINE)
			tw.tween_property(b, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_SINE)
			tw.tween_property(b, "scale", Vector2.ONE * 1.06, 0.1).set_trans(Tween.TRANS_SINE)
			tw.tween_property(b, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_SINE)
			tw.tween_interval(1.1))
	return b

static var _confetti_tex: ImageTexture

static func _confetti(parent: Control, n := 28) -> CPUParticles2D:
	# 0.31.203: confetti drifting down over the sale's stage -- little gold, red, white and pale gold slips, turning
	if _confetti_tex == null:
		var im := Image.create(2, 4, false, Image.FORMAT_RGBA8)
		im.fill(Color.WHITE)
		_confetti_tex = ImageTexture.create_from_image(im)
	var cp := CPUParticles2D.new()
	cp.texture = _confetti_tex
	cp.amount = n
	cp.lifetime = 5.0
	cp.preprocess = 5.0
	cp.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	cp.direction = Vector2(0, 1)
	cp.spread = 25.0
	cp.gravity = Vector2(0, 18)
	cp.initial_velocity_min = 18.0
	cp.initial_velocity_max = 40.0
	cp.angle_min = 0.0
	cp.angle_max = 360.0
	cp.angular_velocity_min = -220.0
	cp.angular_velocity_max = 220.0
	cp.scale_amount_min = 1.4
	cp.scale_amount_max = 2.4
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	g.offsets = PackedFloat32Array([0.0, 0.3, 0.55, 0.75])
	g.colors = PackedColorArray([Color("#ffd04a"), Color("#ff4a3d"), Color("#fff6dc"), Color("#ffb21e")])
	cp.color_initial_ramp = g
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.8, 1.0])
	fade.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	cp.color_ramp = fade
	parent.add_child(cp)
	var place := func():
		cp.position = Vector2(parent.size.x * 0.5, -6.0)
		cp.emission_rect_extents = Vector2(parent.size.x * 0.5, 4.0)
	parent.resized.connect(place)
	UI2.when_ready(cp, place)
	return cp

static func _struck(parent: Node, s: String, size: int, color: Color) -> Label:
	# a price no longer asked: greyed, a red line through it
	var l := UI.label(parent, s, size, color, UI.HEAVY_FONT)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 3)
	var line := ColorRect.new()
	line.color = Color("#ff3b30")
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.anchor_right = 1.0
	line.anchor_top = 0.5
	line.anchor_bottom = 0.5
	line.offset_left = -2.0
	line.offset_right = 2.0
	line.offset_top = -1.0
	line.offset_bottom = 1.5
	line.rotation = deg_to_rad(-10.0)
	line.resized.connect(func(): line.pivot_offset = line.size * 0.5)
	l.add_child(line)
	return l

static func _scroll_to(app, node) -> void:
	# glide the page so `node` sits at the top (the shop's jump bar and role coins)
	var sc: ScrollContainer = app.content_scroll
	if not is_instance_valid(sc) or node == null or not is_instance_valid(node):
		return
	var to := maxi(0, sc.scroll_vertical + int((node as Control).global_position.y - sc.global_position.y) - 8)
	var tw := sc.create_tween()
	tw.tween_property(sc, "scroll_vertical", to, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

static func _twinkles(parent: Control, n: int, col: Color, area: Rect2, px := 22.0) -> void:
	# little four-point stars winking on and off over a picture (area: fractions of the parent), each on its own beat
	for i in n:
		var t := TextureRect.new()
		t.texture = UI2.tex("res://assets/vfx/spell/sparkle.png")
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		var sz := px * randf_range(0.6, 1.2)
		t.size = Vector2(sz, sz)
		t.pivot_offset = t.size * 0.5
		t.modulate = Color(col, 0.0)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		t.material = mat
		parent.add_child(t)
		var fx := randf_range(area.position.x, area.position.x + area.size.x)
		var fy := randf_range(area.position.y, area.position.y + area.size.y)
		var place := func(): t.position = Vector2(parent.size.x * fx, parent.size.y * fy) - t.size * 0.5
		parent.resized.connect(place)
		UI2.when_ready(t, func():
			place.call()
			var tw := t.create_tween().set_loops()
			tw.tween_interval(randf_range(0.2, 3.0))
			tw.tween_property(t, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_SINE)
			tw.parallel().tween_property(t, "rotation", deg_to_rad(45.0), 0.7)
			tw.tween_property(t, "modulate:a", 0.0, 0.45).set_trans(Tween.TRANS_SINE)
			tw.tween_property(t, "rotation", 0.0, 0.01)
			tw.tween_interval(randf_range(1.5, 3.5)))

static func _feat_thumb(app, row: Node, id: String, i: int, on: bool) -> void:
	# one of the week's three: him in it over his own place, a gold frame on the one showing
	var sk: Dictionary = Eco.SKINS[id]
	var hid := str(sk.hero)
	var rc := Color(str(Eco.RARITY_COLOR.get(str(sk.rarity), "#c47bff")))
	var tb := Button.new()
	tb.flat = true
	tb.focus_mode = Control.FOCUS_NONE
	for st_name in ["normal", "hover", "pressed", "focus"]:
		tb.add_theme_stylebox_override(st_name, StyleBoxEmpty.new())
	tb.custom_minimum_size = Vector2(76, 76)
	tb.set_meta("action_key", "feat_%d" % i)
	tb.pressed.connect(func():
		app.sfx("tap")
		app.set_meta("shop_feat", i)
		app.rebuild())
	row.add_child(tb)
	var pane := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Champions.accent(hid).darkened(0.75)
	sb.set_corner_radius_all(16)
	pane.add_theme_stylebox_override("panel", sb)
	pane.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	pane.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tb.add_child(pane)
	var art := TextureRect.new()
	art.texture = UI2.tex(Champions.card_art(hid))
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.modulate = Color(1, 1, 1) if on else Color(0.55, 0.55, 0.65)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.add_child(art)
	var ti := UI2.img(pane, "res://assets/ui/skins/%s.png" % id, 70.0)
	ti.position = Vector2(3, 6)
	if not on:
		ti.modulate = Color(0.75, 0.75, 0.82)
	var rim := Panel.new()
	var rs := StyleBoxFlat.new()
	rs.draw_center = false
	rs.border_color = UI2.GOLD if on else Color(rc, 0.8)
	rs.set_border_width_all(3 if on else 2)
	rs.set_corner_radius_all(16)
	if on:
		rs.shadow_color = Color(1.0, 0.82, 0.3, 0.6)
		rs.shadow_size = 8
	rim.add_theme_stylebox_override("panel", rs)
	rim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tb.add_child(rim)
	var off := Eco.sale_off(id, int(app.profile.now()))        # 0.31.203: its discount on the corner
	if off > 0:
		var bd := _sale_badge(tb, off, 42.0, true)
		bd.position = Vector2(46, -14)

static func gem_packs(app, root: Node) -> Control:
	# 0.31.90 (Kevin: in-app purchases): gems for real money, Google Play only. The starter pack first while it can still
	# be bought, then the five packs, priced in the player's currency once Google has answered. (0.31.202: returns its
	# heading -- the shop's GEMS jump)
	var bl = app.billing
	var live: bool = bl != null and bl.active()
	# (0.31.130: the App Store on iOS; the same words otherwise)
	var head := UI2.divider(root, "GEM PACKS", 22, ("%s  ·  gems never change damage" if live else "in the %s version") % Platform.store_short())
	var p = app.profile
	if not bool(p.d.iap.starter):
		var sc := Control.new()
		sc.custom_minimum_size = Vector2(0, 132)
		root.add_child(sc)
		UI2.plate(sc, "ember", 18.0, "orange")
		var ry := UI2.rays(sc, 200.0, Color(1.0, 0.8, 0.4), 26.0, 0.35)
		ry.position = Vector2(-40, -40)
		var gi := UI2.img(sc, "res://assets/ui/packs/gem_pack_2.png", 96.0)
		gi.position = Vector2(12, 16)
		UI2.bob(gi, 4.0, 1.4)                                       # (0.31.202: it floats, it shines, it says once)
		_twinkles(sc, 5, Color(0.8, 0.95, 1.0), Rect2(0.04, 0.1, 0.24, 0.7), 18.0)
		UI2.sweep(sc, 3.6, 80.0, 0.3)
		var once := UI2.chip(sc, "ONE-TIME OFFER", Color("#e8443a"), Color.WHITE, Color("#3a0805"))
		once.anchor_left = 1.0
		once.anchor_right = 1.0
		once.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		once.offset_right = -10
		once.offset_left = -120
		once.offset_top = -9
		once.offset_bottom = 9
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 120
		v.offset_right = -12
		v.offset_top = 10
		v.offset_bottom = -52
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sc.add_child(v)
		UI2.text(v, "STARTER PACK", 20, UI2.GOLD, UI2.INK, 5)
		var sp: Dictionary = Net.IAP.starter_pack
		UI2.body(v, "%d gems  ·  %s gold  ·  a Hero Token (any hero)  ·  once per player" % [int(sp.gems), UI.grouped(int(sp.get("gold", 0)))],
			12, Color("#ffe9c7"))            # (0.31.108-0.31.187: an epic weapon)
		var sb := _iap_button(app, sc, "starter_pack", Vector2.ZERO, Vector2.ZERO)
		sb.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		sb.offset_left = 120
		sb.offset_right = -12
		sb.offset_top = -48
		sb.offset_bottom = -10
	# 0.31.108: a "play_only" pack (gems_14000) shows once Google Play knows its price; then it is the best value
	var shown := []
	for pid in Net.IAP:
		var pk0: Dictionary = Net.IAP[pid]
		if bool(pk0.get("once", false)):
			continue
		if bool(pk0.get("play_only", false)) and not (app.billing != null and app.billing.prices.has(pid)):
			continue
		shown.append(pid)
	var grids := []
	for cols in [3, maxi(2, shown.size() - 3)]:
		var grid := GridContainer.new()
		grid.columns = cols
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 10)
		root.add_child(grid)
		grids.append(grid)
	var size_ix := 0
	for pid in shown:
		var pk: Dictionary = Net.IAP[pid]
		var grid: GridContainer = grids[0 if size_ix < 3 else 1]
		var c := Control.new()
		var big := size_ix >= 3
		UI.grow(c)
		grid.add_child(c)
		UI2.plate(c, "purple" if big else "royal", 18.0, "gold" if big else "blue")
		var art_px := pack_art(c, "res://assets/ui/packs/gem_pack_%d.png" % mini(size_ix + 1, 6), mini(size_ix + 1, 5), big,
			Color(0.55, 0.85, 1.0))
		var gl := UI2.text(c, UI.compact(int(pk.gems)), 21 if big else 19, Color.WHITE, UI2.INK, 5)
		gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		gl.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		gl.offset_top = art_px + 8.0
		gl.offset_bottom = art_px + 32.0
		var b := _iap_button(app, c, pid, Vector2.ZERO, Vector2.ZERO)
		b.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		b.offset_left = 6
		b.offset_right = -6
		b.offset_top = -40
		b.offset_bottom = -6
		var tag := str(pk.get("tag", ""))
		if tag == "BEST VALUE" and pid != shown[shown.size() - 1]:
			tag = ""                                    # (a bigger pack is the best value)
		if tag == "BEST VALUE":
			UI2.sweep(c, 3.0, 70.0, 0.32)                          # (0.31.202: the best value shines)
		if tag != "":
			var tg := UI2.chip(c, tag, Color("#e8443a") if tag == "BEST VALUE" else Color("#2f7de1"), Color.WHITE, Color("#170a05"))
			tg.anchor_left = 0.5
			tg.anchor_right = 0.5
			tg.offset_left = -46
			tg.offset_right = 46
			tg.offset_top = -10
			tg.offset_bottom = 8
		size_ix += 1
	if StoreBilling.can_restore(bl):
		# 0.31.130: the App Store requires a way to get a bought-once item (the starter pack) back on a new phone
		var rb := UI2.button(root, "…" if bool(bl.restoring) else "RESTORE PURCHASES", "grey", func():
			app.sfx("tap")
			bl.restore(), "iap_restore", 14, 38.0)
		rb.disabled = bool(bl.restoring) or str(bl.busy) != ""
	return head

static func pack_art(c: Control, path: String, tier: int, big: bool, shine: Color) -> float:
	# 0.31.106 (Kevin: "Make new art for the higher tier packs so it shows more the higher the pack is. Add fun things
	# to art for higher packs"): each tier its own picture, bigger as it goes (a gem, a heap, a pouch, a chest, a royal
	# hoard with a crown and a baby dragon; a stack ... a barrel, a mine cart with a grinning mimic). The top two shine
	# (a soft glow); the top one also has turning rays and bobs. Sets the tile's height; returns the art's size.
	var px := 104.0 if not big else 132.0
	c.custom_minimum_size = Vector2(0, px + 84.0)
	if tier >= 4:
		var gw := UI2.glow(c, Rect2(0, 0, 10, 10), Color(shine, 0.5 if tier == 5 else 0.32))
		c.resized.connect(func():
			gw.size = Vector2(px, px) * 1.25
			gw.position = Vector2((c.size.x - gw.size.x) * 0.5, 6.0 + (px - gw.size.y) * 0.5))
	if tier >= 5:
		var ry := UI2.rays(c, px * 1.6, Color(shine.lerp(Color.WHITE, 0.4)), 22.0, 0.42)
		c.resized.connect(func(): ry.position = Vector2((c.size.x - ry.size.x) * 0.5, 6.0 + (px - ry.size.y) * 0.5))
	var gi := UI2.img(c, path, px)
	c.resized.connect(func(): gi.position = Vector2((c.size.x - px) * 0.5, 6.0))
	if tier >= 5:
		UI2.when_ready(gi, func():
			var tw := gi.create_tween().set_loops()
			tw.tween_property(gi, "position:y", 1.0, 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tw.tween_property(gi, "position:y", 9.0, 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT))
	return px

static func _iap_button(app, parent: Control, pid: String, at: Vector2, sz: Vector2) -> Button:
	var bl = app.billing
	var live: bool = bl != null and bl.active()
	var label := Platform.store_button()                # "PLAY STORE" (0.31.130: "APP STORE" on iOS)
	if live:
		label = "…" if str(bl.busy) == pid else str(bl.price(pid))
	var b := UI2.button(parent, label, "green" if live else "grey", func():
		app.sfx("tap")
		if bl != null:
			bl.buy(pid)
		else:
			app.toast("Gem packs are sold in the %s version of Fatebound" % Platform.store_short(), UI.RED), "iap_" + pid, 15, 34.0, 11.0)
	if sz != Vector2.ZERO:
		b.position = at
		b.size = sz
	if live:
		b.disabled = not bl.can_buy(pid)
	return b

# ---------------- hero skins (0.31.186, League's way) ----------------
# Every skin (Eco.SKINS): the hero in it (assets/ui/skins/<id>.png, tools/render_skin_icons.gd), its name, its gems --
# BUY asks first (a skin of a locked hero brings him: "+ HERO" on the card); one you own WEAR / WORN (tap WORN: his own
# look again). The hero window has the same choice beside the hero.
static func featured_outfit(app, root: Node, id: String) -> void:
	# 0.31.188: one of the week's outfits big -- the hero in it, turning, in front of his own place (Champions.art), its
	# name, his name, its price; tap: his window with it on (preview, buy, wear)
	# 0.31.203 (Kevin: "For featured outfits, let's make them discounted ... make the graphic of the features look very
	# eye catching"): the WEEKLY SALE's stage -- a treasure hall, its curtains drawn back (ElevenLabs art), him on its
	# pedestal under the light, rays of his rarity turning behind him, confetti falling, the red-and-gold starburst with
	# the discount beating on the corner, the full price struck through and the sale's on a shining button
	var p = app.profile
	var sk: Dictionary = Eco.SKINS[id]
	var hid := str(sk.hero)
	var offer := Eco.skin_offer(id, p.now())
	var off := int(offer.off)
	var owned: bool = p.owns_skin(id)
	var low := view_low(app)
	var fc := Control.new()
	fc.custom_minimum_size = Vector2(0, 300)
	root.add_child(fc)
	var stage := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.02, 0.03)
	sb.set_corner_radius_all(20)
	stage.add_theme_stylebox_override("panel", sb)
	stage.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fc.add_child(stage)
	var art := TextureRect.new()
	art.texture = UI2.tex(SALE + "sale_stage.webp")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(art)
	var rcol := Color(str(Eco.RARITY_COLOR.get(str(sk.rarity), "#c47bff")))
	var warm := rcol.lerp(Color(1.0, 0.8, 0.35), 0.45)
	# a dark wash on the right for the words (0.31.202), deeper now the hall behind is bright
	var wash := TextureRect.new()
	var wg := Gradient.new()
	wg.set_color(0, Color(0.1, 0.0, 0.02, 0.0))
	wg.set_color(1, Color(0.1, 0.0, 0.02, 0.82))
	var wt := GradientTexture2D.new()
	wt.gradient = wg
	wt.fill_from = Vector2(0.4, 0.5)
	wt.fill_to = Vector2(0.75, 0.5)
	wt.width = 64
	wt.height = 4
	wash.texture = wt
	wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(wash)
	var rays := UI2.rays(stage, 340.0, warm, 24.0, 0.5)
	var halo := UI2.glow(stage, Rect2(0, 0, 240, 240), Color(warm, 0.5))
	var pool := UI2.glow(stage, Rect2(0, 0, 210, 48), Color(1.0, 0.86, 0.5, 0.65), false)
	fc.resized.connect(func():
		# the hall sized and slid so its pedestal (at 30.5 % across, 63.5 % down the picture) is under his feet
		var cx := fc.size.x * 0.31
		var feet := fc.size.y * SALE_FEET
		var ah := maxf(fc.size.y, feet / 0.635)
		var aw := ah * 16.0 / 9.0
		art.size = Vector2(aw, ah)
		art.position = Vector2(clampf(cx - 0.305 * aw, fc.size.x - aw, 0.0), minf(0.0, feet - 0.635 * ah))
		rays.position = Vector2(cx - 170.0, fc.size.y * 0.42 - 170.0)
		halo.position = Vector2(cx - 120.0, fc.size.y * 0.42 - 120.0)
		pool.position = Vector2(cx - 105.0, feet - 24.0))
	var sh := Showcase.new()
	sh.plinth = false
	sh.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sh.anchor_right = 0.62
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(sh)
	sh.show_look(hid, {"skin": id})
	if not low:
		_confetti(stage)
		_twinkles(stage, 7, rcol.lerp(Color.WHITE, 0.6), Rect2(0.05, 0.1, 0.5, 0.75), 20.0)
	var rim := Panel.new()
	var rs := StyleBoxFlat.new()
	rs.draw_center = false
	rs.border_color = UI2.GOLD                                # (0.31.203: the sale's gold; 0.31.202 its rarity)
	rs.set_border_width_all(3)
	rs.set_corner_radius_all(20)
	rs.shadow_color = Color(1.0, 0.55, 0.15, 0.55)
	rs.shadow_size = 12
	rim.add_theme_stylebox_override("panel", rs)
	rim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fc.add_child(rim)
	var cap := VBoxContainer.new()
	cap.add_theme_constant_override("separation", 3)
	cap.anchor_left = 0.56
	cap.anchor_right = 1.0
	cap.offset_top = 16
	cap.offset_right = -12
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fc.add_child(cap)
	UI2.icon_chip(cap, UI2.icon_path("crown"), str(sk.rarity).to_upper() + "  ·  " + str(Eco.SKIN_HEROES.get(hid, hid)).to_upper(),
		rcol, Color("#120a02"))
	var nl := UI2.text(cap, str(sk.set).to_upper(), 24, Color.WHITE, Color("#3a0306"), 6)
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UI2.body(cap, "%s, the %s" % [Champions.name_of(hid), str(Eco.SKIN_HEROES.get(hid, hid))], 11, Champions.accent(hid).lightened(0.45))
	if not owned and off > 0:
		# the full price struck through, and what you keep
		var was := HBoxContainer.new()
		was.add_theme_constant_override("separation", 5)
		was.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cap.add_child(was)
		UI2.img(was, "res://assets/ui/currency/gem.png", 16.0)
		_struck(was, UI.grouped(int(offer.was_gems)), 15, Color(0.82, 0.8, 0.88))
		UI2.chip(was, "SAVE %s" % UI.grouped(int(offer.was_gems) - int(offer.gems)), Color("#1f7a34"), Color.WHITE, Color("#9dff8a", 0.6))
	if not owned and int(offer.gold) > 0:                    # 0.31.189: a rare outfit -- or gold (0.31.203: on sale too)
		var gr := HBoxContainer.new()
		gr.add_theme_constant_override("separation", 4)
		gr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cap.add_child(gr)
		UI2.body(gr, "or", 11, Color("#ffd86b"), false)
		if off > 0:
			_struck(gr, UI.grouped(int(offer.was_gold)), 11, Color(0.8, 0.78, 0.7))
		UI2.body(gr, "%s gold" % UI.grouped(int(offer.gold)), 11, Color("#ffd86b"), false)
	UI2.body(cap, "Tap to see it on him", 10, Color(1, 1, 1, 0.65))
	var tap := Button.new()
	tap.flat = true
	tap.focus_mode = Control.FOCUS_NONE
	for st_name in ["normal", "hover", "pressed", "focus"]:
		tap.add_theme_stylebox_override(st_name, StyleBoxEmpty.new())
	tap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tap.set_meta("action_key", "feat_open")
	tap.pressed.connect(func(): app.open_champion(hid, id))
	fc.add_child(tap)
	var b: Button
	if owned:
		var worn: bool = p.worn_skin(hid) == id
		b = UI2.button(fc, "WORN" if worn else "WEAR", "grey" if worn else "blue", func():
			p.wear_skin(hid, "" if p.worn_skin(hid) == id else id)
			app.sfx("equip")
			app.rebuild(), "feat_wear", 16, 44.0, 12.0)
	else:
		b = UI2.button(fc, UI.grouped(int(offer.gems)), "purple", func(): buy_skin(app, id), "feat_buy", 19, 48.0, 13.0,
			"res://assets/ui/currency/gem.png")
		b.disabled = not can_buy_skin(p, id)
		if not b.disabled:
			UI2.sweep(b, 2.0, 50.0, 0.5)
			if not low:
				UI2.pulse(b, 0.035, 0.7)
	b.anchor_left = 0.58
	b.anchor_right = 1.0
	b.anchor_top = 1.0
	b.anchor_bottom = 1.0
	b.offset_right = -12
	b.offset_top = -62
	b.offset_bottom = -12
	if off > 0:
		var bd := _sale_badge(fc, off, 104.0, low)
		bd.position = Vector2(-12, -16)

static func skin_grid(app, root: Node) -> void:
	# 0.31.202: the outfits by role, the Locker's order (TANK ... SUPPORT) -- a row of the six roles' coins first, each
	# jumping to its own; a role: its name, its heroes, then three to a row: their sets on top, the Frostbound line under
	var Kits = load("res://scripts/siege/moba_kits.gd")          # (loaded here, not at boot: the 5v5's)
	var heads := {}
	var coins := HBoxContainer.new()
	coins.alignment = BoxContainer.ALIGNMENT_CENTER
	coins.add_theme_constant_override("separation", 6)
	root.add_child(coins)
	for role in ROLE_ORDER:
		var rl: String = role
		_role_coin(coins, rl, str(Kits.ROLE_NAMES.get(rl, rl)), func():
			app.sfx("tap")
			_scroll_to(app, heads.get(rl)))
	for role in ROLE_ORDER:
		var heroes: Array = Champions.ORDER.filter(func(h): return Kits.role_of(str(h)) == role and not Eco.skins_of(str(h)).is_empty())
		if heroes.is_empty():
			continue
		var rh := HBoxContainer.new()
		rh.add_theme_constant_override("separation", 8)
		root.add_child(rh)
		heads[role] = rh
		var bp := "res://assets/ui/roles/%s.png" % role
		if ResourceLoader.exists(bp):
			var bi := UI2.img(rh, bp, 30.0)
			bi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var rt := UI2.text(rh, str(Kits.ROLE_NAMES.get(role, role)), 19, UI2.GOLD, UI2.INK, 5)
		rt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var names := heroes.map(func(h): return str(Eco.SKIN_HEROES.get(str(h), h)))
		var rs := UI2.body(rh, "  ·  ".join(names), 10, UI2.SOFT, true)
		rs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rs.custom_minimum_size.x = 10
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 12)
		root.add_child(grid)
		var ids := []
		for frost in [false, true]:
			for h in heroes:
				for id in Eco.skins_of(str(h)):
					if (str(Eco.SKINS[id].get("line", "")) in Eco.SKIN_LINES) == frost:
						ids.append(str(id))
		for id in ids:
			outfit_card(app, grid, str(id))

static func _role_coin(row: Node, role: String, label: String, on_press: Callable) -> Button:
	# a round button with the role's emblem and its name under it (the shop's jump to that role)
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	for st_name in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st_name, StyleBoxEmpty.new())
	b.custom_minimum_size = Vector2(58, 64)
	b.set_meta("action_key", "shop_role_" + role)
	b.pressed.connect(on_press)
	row.add_child(b)
	var disc := Control.new()
	disc.position = Vector2(6, 0)
	disc.size = Vector2(46, 46)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(disc)
	UI2.plate(disc, "royal", 23.0, "gold", {"rim": 2.0})
	var ic := UI2.img(disc, "res://assets/ui/roles/%s.png" % role, 34.0)
	ic.position = Vector2(6, 6)
	var l := UI.label(b, label, 9, UI2.CREAM, UI.HEAVY_FONT)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", UI2.INK)
	l.add_theme_constant_override("outline_size", 3)
	l.position = Vector2(-4, 48)
	l.size = Vector2(66, 14)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b

static func _grad_rect(parent: Control, stops: Array, from := Vector2(0, 0), to := Vector2(0, 1)) -> TextureRect:
	# a full-size gradient over the parent: stops = [[offset, Color], ...]
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for st in stops:
		offs.append(float(st[0]))
		cols.append(st[1])
	g.offsets = offs
	g.colors = cols
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = from
	gt.fill_to = to
	gt.width = 4
	gt.height = 64
	var t := TextureRect.new()
	t.texture = gt
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)
	return t

static func outfit_card(app, grid: Node, id: String, armory := false) -> Control:
	# 0.31.202: one outfit -- the hero in it standing in his own place (Champions.card_art; the Frostbound line's
	# frosted over), a glow of its rarity behind him (a set: turning rays too), its rarity and whether you own it or wear
	# it, the set's name and the hero's, "or 40K" gold for the Frostbound line; tap the picture: his window with it on;
	# the button: its gems (BUY asks first), WEAR, WORN
	var p = app.profile
	var sk: Dictionary = Eco.SKINS[id]
	var hid := str(sk.hero)
	var rar := str(sk.rarity)
	var frost: bool = str(sk.get("line", "")) in Eco.SKIN_LINES
	var rc := Color(str(Eco.RARITY_COLOR.get(rar, "#c47bff")))
	var owned: bool = p.owns_skin(id)
	var worn: bool = owned and p.worn_skin(hid) == id
	var acc: Color = Champions.accent(hid)
	var offer := Eco.skin_offer(id, p.now())                 # 0.31.203: the weekly sale's price when it's on it
	var sale: bool = int(offer.off) > 0 and not owned
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 226)
	UI.grow(c)
	grid.add_child(c)
	var pane := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = rc.darkened(0.82)
	sb.set_corner_radius_all(16)
	pane.add_theme_stylebox_override("panel", sb)
	pane.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	pane.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(pane)
	var art := TextureRect.new()
	art.texture = UI2.tex(Champions.card_art(hid))
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.offset_bottom = -52
	art.modulate = Color(0.62, 0.8, 1.0) if frost else Color(0.92, 0.88, 1.0)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.add_child(art)
	if frost:
		_grad_rect(pane, [[0.0, Color(0.85, 0.95, 1.0, 0.45)], [0.35, Color(0.7, 0.88, 1.0, 0.0)]])       # (a frost glaze)
	var rays: TextureRect = null
	if not frost:
		rays = UI2.rays(pane, 190.0, rc.lerp(Color.WHITE, 0.3), 28.0, 0.38)
	var halo := UI2.glow(pane, Rect2(0, 0, 150, 150), Color(rc, 0.55 if not frost else 0.42), false)
	var pool := UI2.glow(pane, Rect2(0, 0, 110, 26), Color(0, 0, 0, 0.55), false)        # (his shadow)
	var ti := UI2.img(pane, "res://assets/ui/skins/%s.png" % id, 128.0)
	_grad_rect(pane, [[0.0, Color(0, 0, 0, 0)], [0.48, Color(0, 0, 0, 0)], [0.7, Color(rc.darkened(0.85), 0.9)], [1.0, Color(rc.darkened(0.88), 1.0)]])
	c.resized.connect(func():
		var cx := c.size.x * 0.5
		ti.position = Vector2(cx - 64.0, 14.0)
		halo.position = Vector2(cx - 75.0, 4.0)
		pool.position = Vector2(cx - 55.0, 128.0)
		if rays != null:
			rays.position = Vector2(cx - 95.0, 78.0 - 95.0))
	if frost and not view_low(app):
		_twinkles(pane, 3, Color(0.85, 0.95, 1.0), Rect2(0.1, 0.08, 0.8, 0.5), 14.0)
	var rim := Panel.new()
	var rs := StyleBoxFlat.new()
	rs.draw_center = false
	rs.border_color = UI2.GOLD if worn else rc
	rs.set_border_width_all(3 if worn else 2)
	rs.set_corner_radius_all(16)
	rs.shadow_color = Color(UI2.GOLD, 0.55) if worn else Color(rc, 0.3)
	rs.shadow_size = 7 if worn else 4
	rim.add_theme_stylebox_override("panel", rs)
	rim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(rim)
	# its rarity (left), and the hero coming with it / owned / worn (right)
	var tag := _card_tag(c, rar.to_upper(), rc.darkened(0.15), rc.darkened(0.7))
	tag.position = Vector2(6, 6)
	var right := ""
	var rfill := Color("#2f8a3e")
	if worn:
		right = "WORN"
		rfill = Color("#b8861c")
	elif owned and not armory:                     # (0.31.204: in the Armory everything is yours)
		right = "OWNED ✓"
	elif not p.owns_hero(hid):
		right = "+ HERO"
	if right != "" and sale:
		var hc := _card_tag(c, right, rfill, rfill.darkened(0.7))       # (the corner is the sale's: under the rarity)
		hc.position = Vector2(6, 24)
	elif right != "":
		var hc := _card_tag(c, right, rfill, rfill.darkened(0.7))
		hc.anchor_left = 1.0
		hc.anchor_right = 1.0
		hc.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		hc.offset_right = -6
		hc.offset_left = -60
		hc.offset_top = 6
		hc.offset_bottom = 22
	# the names over the foot of the picture
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	v.offset_top = -100
	v.offset_bottom = -46
	v.offset_left = 4
	v.offset_right = -4
	v.alignment = BoxContainer.ALIGNMENT_END
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(v)
	var set_name := str(sk.set).to_upper()
	var nl := UI2.text(v, set_name, 14 if set_name.length() <= 10 else (12 if set_name.length() <= 12 else 11), Color.WHITE, UI2.INK, 4)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.autowrap_mode = TextServer.AUTOWRAP_OFF
	nl.clip_text = true
	var hl := UI.label(v, str(Eco.SKIN_HEROES.get(hid, hid)).to_upper(), 10, acc.lerp(Color.WHITE, 0.45), UI.HEAVY_FONT)
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hl.autowrap_mode = TextServer.AUTOWRAP_OFF
	hl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hl.add_theme_constant_override("outline_size", 3)
	if not owned and int(offer.gold) > 0:                 # 0.31.189: or gold (0.31.203: the sale's)
		var gc := UI2.icon_chip(v, "res://assets/ui/currency/coin.png", "or %dK" % (int(offer.gold) / 1000), Color(0.18, 0.12, 0.02, 0.85),
			Color("#ffd86b"), Color("#ffd86b", 0.5))
		gc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	elif sale:                                            # what it was, struck through
		var wr := HBoxContainer.new()
		wr.alignment = BoxContainer.ALIGNMENT_CENTER
		wr.add_theme_constant_override("separation", 3)
		wr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(wr)
		UI2.img(wr, "res://assets/ui/currency/gem.png", 12.0)
		_struck(wr, str(int(offer.was_gems)), 11, Color(0.8, 0.78, 0.86))
	var look := Button.new()                         # 0.31.188: tap the card -- his window with it on
	look.flat = true
	look.focus_mode = Control.FOCUS_NONE
	for st_name in ["normal", "hover", "pressed", "focus"]:
		look.add_theme_stylebox_override(st_name, StyleBoxEmpty.new())
	look.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	look.offset_bottom = -46
	look.set_meta("action_key", "skin_look_" + id)
	look.pressed.connect(func(): app.open_champion(hid, id, armory))
	c.add_child(look)
	var b: Button
	if owned:
		b = UI2.button(c, "WORN" if worn else "WEAR", "gold" if worn else "blue", func():
			p.wear_skin(hid, "" if p.worn_skin(hid) == id else id)
			app.sfx("equip")
			app.rebuild(), "skin_wear_" + id, 13, 34.0, 11.0)
	else:
		b = UI2.button(c, str(int(offer.gems)), "purple", func(): buy_skin(app, id), "skin_buy_" + id, 14, 34.0, 11.0,
			"res://assets/ui/currency/gem.png")
		b.disabled = not can_buy_skin(p, id)
	b.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	b.offset_left = 7
	b.offset_right = -7
	b.offset_top = -42
	b.offset_bottom = -7
	if sale:
		rs.border_color = Color("#ffcf4a")                   # (a sale: a gold frame, glowing warm)
		rs.shadow_color = Color(1.0, 0.5, 0.15, 0.5)
		rs.shadow_size = 7
		var bd := _sale_badge(c, int(offer.off), 50.0, view_low(app))
		c.resized.connect(func(): bd.position = Vector2(c.size.x - 40.0, -10.0))
	return c

# ---------------- the Market's HEROES (0.31.204) ----------------
static func market_heroes(app, root: VBoxContainer) -> void:
	# 0.31.204 (Kevin: "put a hero tab in the market that shows heroes that player doesn't own and that's where they will
	# purchase them"): every hero you don't own, by role (TANK ... SUPPORT), on cards like the outfits' -- him in his
	# own place, FREE THIS WEEK / NEW / a shard of him, his gold and gem price, UNLOCK (gold, gems, a shard, a Hero Token;
	# asked first); tap the picture: his window (story, kit, outfits). Once he's yours he's in the Armory. The 5v5
	# picker's GET IN MARKET lands here with his card lit (app.open_market("heroes", hid)).
	var p = app.profile
	var Kits = load("res://scripts/siege/moba_kits.gd")          # (loaded here, not at boot: the 5v5's)
	var locked: Array = Champions.ORDER.filter(func(h): return not p.owns_hero(str(h)))
	UI2.divider(root, "HEROES", 22, "yours for good  ·  gold or gems  ·  then he's in your Armory")
	var inv := ""
	if int(p.d.get("tokens", 0)) > 0:
		inv = "HERO TOKEN x%d" % int(p.d.tokens)
	var nsh := (p.d.get("shards", []) as Array).size()
	if nsh > 0:
		inv += ("  ·  " if inv != "" else "") + "◆ SHARD%s %d" % ["S" if nsh > 1 else "", nsh]
	if inv != "" and not locked.is_empty():
		var ic := UI2.chip(root, inv, Color("#173a1e"), Color("#c9f7bd"), Color("#6be07c"))
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if locked.is_empty():
		# every hero is yours
		var box := UI2.frame(root, "night", 16, 18.0, "gold")
		box.add_theme_constant_override("separation", 6)
		var cr := UI2.img(box, UI2.icon_path("crown"), 64.0)
		cr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		UI2.center(UI2.text(box, "EVERY HERO IS YOURS", 22, Color.WHITE))
		UI2.center(UI2.body(box, "All %d of them -- they're waiting in your Armory." % Champions.ORDER.size(), 12, UI2.SOFT))
		var ab := UI2.button(box, "OPEN THE ARMORY", "gold", func():
			app.sfx("tab")
			app.locker_tab = "heroes"
			app.show_tab("locker"), "market_to_armory", 15, 42.0, 12.0)
		ab.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		return
	var free: Array = Eco.free_heroes(p.now()).filter(func(h): return not p.owns_hero(str(h)))
	if not free.is_empty():
		var fc := UI2.chip(root, "FREE THIS WEEK: %s  ·  play them in battle, own them here" % ", ".join(free.map(func(h): return Champions.short_of(str(h)).to_upper())),
			Color("#1f6a2e"), Color.WHITE, Color("#9dff8a", 0.6))
		fc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var focus := str(app.get_meta("shop_hero_focus", ""))
	if app.has_meta("shop_hero_focus"):
		app.remove_meta("shop_hero_focus")
	var lit: Control = null
	for role in ROLE_ORDER:
		var hs: Array = locked.filter(func(h): return Kits.role_of(str(h)) == role)
		if hs.is_empty():
			continue
		var rh := HBoxContainer.new()
		rh.add_theme_constant_override("separation", 8)
		root.add_child(rh)
		var bp := "res://assets/ui/roles/%s.png" % role
		if ResourceLoader.exists(bp):
			UI2.img(rh, bp, 30.0).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UI2.text(rh, str(Kits.ROLE_NAMES.get(role, role)), 19, UI2.GOLD, UI2.INK, 5).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var rs := UI2.body(rh, str(Kits.ROLE_TEXT.get(role, "")), 10, UI2.SOFT, true)
		rs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rs.custom_minimum_size.x = 10
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 12)
		root.add_child(grid)
		for hid in hs:
			var c := hero_offer_card(app, grid, str(hid))
			if str(hid) == focus:
				lit = c
		if hs.size() < 3:                                  # (keep the cards a third wide)
			for i in 3 - hs.size():
				var gap := Control.new()
				UI.grow(gap)
				grid.add_child(gap)
	if lit != null:
		# from the 5v5 picker: glide to his card and light it up
		var ring := Panel.new()
		var rs2 := StyleBoxFlat.new()
		rs2.draw_center = false
		rs2.border_color = Color("#fff3ad")
		rs2.set_border_width_all(4)
		rs2.set_corner_radius_all(18)
		rs2.shadow_color = Color(1.0, 0.8, 0.3, 0.8)
		rs2.shadow_size = 14
		ring.add_theme_stylebox_override("panel", rs2)
		ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ring.offset_left = -3
		ring.offset_top = -3
		ring.offset_right = 3
		ring.offset_bottom = 3
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.set_meta("hero_focus_ring", true)
		lit.add_child(ring)
		UI2.when_ready(ring, func():
			var tw := ring.create_tween().set_loops(4)
			tw.tween_property(ring, "modulate:a", 0.25, 0.4).set_trans(Tween.TRANS_SINE)
			tw.tween_property(ring, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_SINE)
			var glide := ring.create_tween()               # (bound to the ring: gone with the page if you leave first)
			glide.tween_interval(0.12)
			glide.tween_callback(func():
				var sc: ScrollContainer = app.content_scroll
				if is_instance_valid(lit) and is_instance_valid(sc):
					var to := maxi(0, sc.scroll_vertical + int(lit.global_position.y - sc.global_position.y) - 90)
					sc.create_tween().tween_property(sc, "scroll_vertical", to, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)))

static func hero_offer_card(app, grid: Node, hid: String) -> Control:
	# 0.31.204: one hero for sale -- him (in his own look) in his own place (Champions.card_art), a glow of his colour, his
	# name and class, FREE THIS WEEK / NEW / ◆ shard tags, his price in gold and in gems, UNLOCK (asked first: each way);
	# tap the picture: his window
	var p = app.profile
	var acc: Color = Champions.accent(hid)
	var pr: Dictionary = p.hero_price(hid)
	var plays: bool = p.can_play_hero(hid)
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 244)
	UI.grow(c)
	grid.add_child(c)
	var pane := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = acc.darkened(0.82)
	sb.set_corner_radius_all(16)
	pane.add_theme_stylebox_override("panel", sb)
	pane.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	pane.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(pane)
	var art := TextureRect.new()
	art.texture = UI2.tex(Champions.card_art(hid))
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.offset_bottom = -70
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.add_child(art)
	var rays := UI2.rays(pane, 190.0, acc.lerp(Color(1.0, 0.9, 0.6), 0.4), 30.0, 0.32)
	var halo := UI2.glow(pane, Rect2(0, 0, 150, 150), Color(acc.lerp(Color.WHITE, 0.2), 0.5), false)
	var pool := UI2.glow(pane, Rect2(0, 0, 110, 26), Color(0, 0, 0, 0.55), false)
	var ti := UI2.img(pane, "res://assets/ui/skins/default_%s.png" % hid, 128.0)
	_grad_rect(pane, [[0.0, Color(0, 0, 0, 0)], [0.42, Color(0, 0, 0, 0)], [0.62, Color(acc.darkened(0.85), 0.92)], [1.0, Color(acc.darkened(0.9), 1.0)]])
	c.resized.connect(func():
		var cx := c.size.x * 0.5
		ti.position = Vector2(cx - 64.0, 14.0)
		halo.position = Vector2(cx - 75.0, 4.0)
		pool.position = Vector2(cx - 55.0, 128.0)
		rays.position = Vector2(cx - 95.0, 78.0 - 95.0))
	var rim := Panel.new()
	var rs := StyleBoxFlat.new()
	rs.draw_center = false
	rs.border_color = acc.lerp(Color.WHITE, 0.15)
	rs.set_border_width_all(2)
	rs.set_corner_radius_all(16)
	rs.shadow_color = Color(acc, 0.35)
	rs.shadow_size = 5
	rim.add_theme_stylebox_override("panel", rs)
	rim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(rim)
	# tags down the left: FREE this week, NEW (at his launch price), ◆ a shard of him
	var tags := VBoxContainer.new()
	tags.add_theme_constant_override("separation", 3)
	tags.position = Vector2(6, 6)
	tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(tags)
	if plays:
		_card_tag(tags, "FREE", Color("#2f8a3e"), Color("#0a2006"))          # (this week's: the chip over the list says so)
	if Eco.launching(hid, p.now()):
		_card_tag(tags, "NEW", Color("#d9682a"), Color("#3a1402"))
	if p.shards_of(hid) > 0:
		_card_tag(tags, "◆ SHARD", Color("#1f6a2e"), Color("#6be07c"))
	var nsk := Eco.skins_of(hid).size()
	if nsk > 0:
		var oc := _card_tag(c, "%d OUTFIT%s" % [nsk, "" if nsk == 1 else "S"], Color(0.08, 0.04, 0.16, 0.85), Color("#c47bff"))
		oc.anchor_left = 1.0
		oc.anchor_right = 1.0
		oc.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		oc.offset_right = -6
		oc.offset_left = -60
		oc.offset_top = 6
		oc.offset_bottom = 22
	# his name, his class, his prices
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	v.offset_top = -118
	v.offset_bottom = -44
	v.offset_left = 4
	v.offset_right = -4
	v.alignment = BoxContainer.ALIGNMENT_END
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(v)
	var nm := Champions.short_of(hid).to_upper()
	var nl := UI2.text(v, nm, 16 if nm.length() <= 8 else 13, Color.WHITE, acc.darkened(0.75), 5)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.clip_text = true
	var cl := UI.label(v, str(Eco.SKIN_HEROES.get(hid, hid)).to_upper(), 10, acc.lerp(Color.WHITE, 0.5), UI.HEAVY_FONT)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	cl.add_theme_constant_override("outline_size", 3)
	if not pr.is_empty():
		var prow := HBoxContainer.new()
		prow.alignment = BoxContainer.ALIGNMENT_CENTER
		prow.add_theme_constant_override("separation", 3)
		prow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(prow)
		UI2.img(prow, "res://assets/ui/currency/coin.png", 15.0).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UI2.text(prow, _short_gold(int(pr.gold)), 13, UI2.GOLD, Color("#201002"), 3)
		UI2.body(prow, "or", 9, UI2.SOFT, false).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UI2.img(prow, "res://assets/ui/currency/gem.png", 15.0).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UI2.text(prow, str(int(pr.gems)), 13, Color("#cfe9ff"), Color("#0a1238"), 3)
	var look := Button.new()                         # tap the picture: his window
	look.flat = true
	look.focus_mode = Control.FOCUS_NONE
	for st_name in ["normal", "hover", "pressed", "focus"]:
		look.add_theme_stylebox_override(st_name, StyleBoxEmpty.new())
	look.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	look.offset_bottom = -46
	look.set_meta("action_key", "hero_look_" + hid)
	look.pressed.connect(func(): app.open_champion(hid))
	c.add_child(look)
	var b := UI2.button(c, "UNLOCK", "gold", func(): buy_hero(app, hid), "hero_unlock_" + hid, 14, 36.0, 11.0)
	b.disabled = not can_unlock_hero(p, hid)
	if not b.disabled:
		UI2.sweep(b, 3.0, 40.0, 0.4)
	b.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	b.offset_left = 7
	b.offset_right = -7
	b.offset_top = -42
	b.offset_bottom = -7
	return c

static func _short_gold(n: int) -> String:
	# 6,300 / 50K / 1.5K
	if n >= 10000:
		return "%dK" % (n / 1000) if n % 1000 == 0 else "%.1fK" % (n / 1000.0)
	return UI.grouped(n)

static func can_unlock_hero(p, hid: String) -> bool:
	# any of the ways: his gold, his gems, a shard of him and its gold, a Hero Token
	var pr: Dictionary = p.hero_price(hid)
	if pr.is_empty() or p.owns_hero(hid):
		return false
	return int(p.d.gold) >= int(pr.gold) or int(p.d.gems) >= int(pr.gems) or int(p.d.get("tokens", 0)) > 0 \
		or (p.shards_of(hid) > 0 and int(p.d.gold) >= Eco.shard_unlock_gold(hid, p.now()))

static func buy_hero(app, hid: String) -> void:
	# 0.31.204: UNLOCK <NAME>? -- each way (the 5v5 window's chooser, 0.31.185), those you can't pay dimmed; CANCEL
	var p = app.profile
	var pr: Dictionary = p.hero_price(hid)
	if pr.is_empty() or p.owns_hero(hid):
		return
	var done := func(r: Dictionary) -> void:
		if bool(r.get("ok", false)):
			app.sfx("purchase")
			app.toast("%s joins you! He's in your Armory." % Champions.name_of(hid), UI2.GOLD)
			app.refresh_top()
		else:
			app.sfx("error")
			app.toast(str(r.get("error", "Can't unlock")), UI.RED)
		app.rebuild()
	var opts := [
		{"text": "%s GOLD" % UI.grouped(int(pr.gold)), "style": "gold", "key": "hero_buy_gold", "enabled": int(p.d.gold) >= int(pr.gold),
			"call": func(): done.call(p.buy_hero(hid))},
		{"text": "%s GEMS" % UI.grouped(int(pr.gems)), "style": "premium", "key": "hero_buy_gems", "enabled": int(p.d.gems) >= int(pr.gems),
			"call": func(): done.call(p.buy_hero_gems(hid))}]
	if p.shards_of(hid) > 0:
		var sg := Eco.shard_unlock_gold(hid, p.now())
		opts.append({"text": "SHARD + %s GOLD" % UI.grouped(sg), "style": "claim", "key": "hero_buy_shard", "enabled": int(p.d.gold) >= sg,
			"call": func(): done.call(p.use_shard(hid))})
	if int(p.d.get("tokens", 0)) > 0:
		opts.append({"text": "HERO TOKEN", "style": "primary", "key": "hero_buy_token", "enabled": true,
			"call": func(): done.call(p.use_token(hid))})
	app.choose("UNLOCK %s?" % Champions.name_of(hid).to_upper(), "The %s, yours for good.%s" % [str(Eco.SKIN_HEROES.get(hid, hid)),
		"  Launch price for now." if Eco.launching(hid, p.now()) else ""], opts)

static func _card_tag(parent: Control, s: String, fill: Color, border: Color) -> PanelContainer:
	# a small corner tag on a card (EPIC, RARE, + HERO, OWNED, WORN)
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(7)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 0
	sb.content_margin_bottom = 1
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(pc)
	var l := UI.label(pc, s, 9, Color.WHITE, UI.HEAVY_FONT)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return pc

static func view_low(app) -> bool:
	# fewer extras on "reduce motion" (Settings)
	return app.profile != null and bool(app.profile.d.get("settings", {}).get("reduce_motion", false))

static func can_buy_skin(p, id: String) -> bool:
	# the gems for it -- or (0.31.189: a rare outfit) the gold. 0.31.203: at the weekly sale's price when it's on it
	var o := Eco.skin_offer(id, p.now())
	return int(p.d.gems) >= int(o.gems) or (int(o.gold) > 0 and int(p.d.gold) >= int(o.gold))

static func buy_skin(app, id: String) -> void:
	# BUY asks first; Profile.buy_outfit takes the weekly sale's price when the outfit is on it (0.31.203)
	var p = app.profile
	var sk: Dictionary = Eco.SKINS[id]
	var o := Eco.skin_offer(id, p.now())
	var hid := str(sk.hero)
	var with_hero: bool = not p.owns_hero(hid)
	var bought := func(r: Dictionary) -> void:
		if bool(r.get("ok", false)):
			app.sfx("purchase")
			app.toast("%s is yours%s" % [str(sk.name), " -- and the %s" % str(Eco.SKIN_HEROES.get(hid, hid)) if bool(r.get("hero", false)) else ""], UI.GOLD)
			app.refresh_top()
		else:
			app.sfx("error")
			app.toast(str(r.get("error", "Can't buy")), UI.RED)
		app.rebuild()
	var tail := "%s Worn at once -- change it in the shop or the hero window." % ((" The %s comes with it." % str(Eco.SKIN_HEROES.get(hid, hid))) if with_hero else "")
	var sale := ("Weekly sale: %d%% off. " % int(o.off)) if int(o.off) > 0 else ""
	if int(o.gold) > 0:
		# 0.31.189 (Kevin: "Frostbound for gold"): gems or gold
		app.choose("BUY %s?" % str(sk.name).to_upper(), "%s%s gems or %s gold.%s" % [sale, UI.grouped(int(o.gems)), UI.grouped(int(o.gold)), tail], [
			{"text": "%s GEMS" % UI.grouped(int(o.gems)), "style": "premium", "key": "modal_yes", "enabled": int(p.d.gems) >= int(o.gems),
				"call": func(): bought.call(p.buy_outfit(id, false))},
			{"text": "%s GOLD" % UI.grouped(int(o.gold)), "style": "gold", "key": "modal_gold", "enabled": int(p.d.gold) >= int(o.gold),
				"call": func(): bought.call(p.buy_outfit(id, true))}])
		return
	app.confirm("BUY %s?" % str(sk.name).to_upper(), "%s%d gems.%s" % [sale, int(o.gems), tail], "BUY", "premium", func():
		bought.call(p.buy_outfit(id, false)))

static func is_equipped(p, id: String) -> bool:
	# a title worn (0.31.188: titles are all there is to equip)
	return Eco.item(id).get("kind", "") == "title" and str(p.d.title) == id

static func equip(app, id: String) -> void:
	if app.profile.equip(id).ok:
		app.sfx("equip")
		app.toast("Equipped %s" % str(Eco.item(id).name), UI.CYAN)
	app.rebuild()

# ---------------- LOCKER ----------------
static func _class_coin(parent: Node, cls: String, on: bool, key: String, on_press: Callable, label := "", px := 48.0) -> Button:
	# A round class button with the class's render in it (gold when selected).
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	for st_name in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st_name, StyleBoxEmpty.new())
	b.custom_minimum_size = Vector2(px, px + (14.0 if label != "" else 0.0))
	b.set_meta("action_key", key)
	b.pressed.connect(on_press)
	parent.add_child(b)
	var disc := Control.new()
	disc.size = Vector2(px, px)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(disc)
	if on:
		UI2.skin(disc, UI2.button_params("gold", px * 0.5, 3.0).merged({"glow": 7.0, "glow_color": Color(1.0, 0.84, 0.35, 0.8)}, true))
	else:
		UI2.plate(disc, "royal", px * 0.5, "gold", {"rim": 2.0, "dim": 0.15})
	var clip := Control.new()
	clip.position = Vector2(3, 3)
	clip.size = Vector2(px - 6, px - 6)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.add_child(clip)
	var t := TextureRect.new()
	var portrait := "res://assets/ui/skins/default_%s.png" % cls
	t.texture = UI2.tex(portrait if ResourceLoader.exists(portrait) else "res://assets/ui/icons/default_%s.png" % cls)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	t.position = Vector2(-px * 0.1, -px * 0.04)
	t.size = Vector2(px * 1.1, px * 1.1)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(t)
	if label != "":
		var l := UI2.text(b, label, 9, UI2.CYAN if on else Color.WHITE, UI2.INK, 3, false)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.position = Vector2(-10, px + 1)
		l.size = Vector2(px + 20, 12)
	return b

static func locker(app, root: VBoxContainer) -> void:
	# 0.31.79: the vault -- the class picker, the hero on the vault's pedestal, the nameplate and the weapons as cards.
	# 0.31.187 (Kevin: "give every champion a unique name ... a short background story. Put all this in a revamped locker
	# tab"): CHAMPIONS first (the eighteen by role: tap one for his own window, champion_window.gd), then TITLES.
	# (0.31.187: ARMORY, the vault and its weapons -- gone with the weapons, 0.31.188: an outfit is his whole look.)
	# 0.31.204 (Kevin: "Now redo the locker menu. Change the name to armory and only put in there what the player owns"):
	# the ARMORY (the tab keeps its id "locker") -- a painted armory hall (ElevenLabs) with what you hold on it, then
	# three tabs: HEROES (yours, by role; tap one: his window with only his outfits you own), OUTFITS (yours: WEAR /
	# WORN) and TITLES (earned: EQUIP). Nothing to buy and nothing locked: the Market sells heroes and outfits (a way
	# there when there's more to get); a title you haven't earned isn't shown, only how many are left.
	var p = app.profile
	var heroes: Array = Champions.ORDER.filter(func(h): return p.owns_hero(str(h)))
	var outfits: Array = []
	for h in Champions.ORDER:
		for id in Eco.skins_of(str(h)):
			if p.owns_skin(str(id)):
				outfits.append(str(id))
	var titles: Array = _earned_titles(p)
	var ban := banner(root, UI2.V2 + "art_armory.webp", "ARMORY", 176.0)
	var free: Array = Champions.ORDER.filter(func(h): return not p.owns_hero(str(h)) and p.can_play_hero(str(h)))   # 0.31.205
	var hold := UI2.chip(ban, "%d HEROES%s  ·  %d OUTFITS  ·  %d TITLES" % [heroes.size(), (" +%d FREE" % free.size()) if not free.is_empty() else "",
		outfits.size(), titles.size()],
		Color(0.03, 0.02, 0.1, 0.8), UI2.CREAM, Color(UI2.GOLD, 0.6))
	hold.position = Vector2(12, 12)
	if not view_low(app):
		_twinkles(ban, 6, Color(1.0, 0.86, 0.5), Rect2(0.1, 0.1, 0.8, 0.5))
	if str(app.locker_tab) == "champions":
		app.locker_tab = "heroes"                     # (0.31.187-0.31.203's name for it)
	if not (str(app.locker_tab) in ["heroes", "outfits", "titles"]):
		app.locker_tab = "heroes"
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	root.add_child(tabs)
	for t in [["heroes", "HEROES", heroes.size() + free.size(), UI2.icon_path("crown")], ["outfits", "OUTFITS", outfits.size(), UI2.icon_path("helmet")],
			["titles", "TITLES", titles.size(), UI2.icon_path("scroll")]]:
		var tid: String = t[0]
		var on: bool = str(app.locker_tab) == tid
		var tb0 := UI2.button(tabs, "%s %d" % [str(t[1]), int(t[2])], "gold" if on else "blue", func():
			if str(app.locker_tab) == tid:
				return
			app.locker_tab = tid
			app.sfx("tab")
			app.content_scroll.scroll_vertical = 0
			app.rebuild(), "locker_tab_" + tid, 14, 40.0, 12.0, str(t[3]))
		tb0.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	match str(app.locker_tab):
		"outfits":
			armory_outfits(app, root, outfits)
		"titles":
			armory_titles(app, root, titles)
		_:
			locker_champions(app, root)

static func _earned_titles(p) -> Array:
	# the titles you hold, in the Locker's old order: for everyone, then each class's, then the leaderboard's
	var out := []
	for sec in [""] + Eco.HERO_CLASSES:
		var ids := []
		for id in Eco.TITLE_GOALS:
			if str(Eco.TITLE_GOALS[id].cls) == sec and p.owns(id):
				ids.append(id)
		ids.sort_custom(func(a, b): return Eco.TITLE_RARITY_ORDER.find(str(Eco.CATALOG[a].rarity)) < Eco.TITLE_RARITY_ORDER.find(str(Eco.CATALOG[b].rarity)))
		out.append_array(ids)
	for id in Eco.PRIZE_TITLES:
		if p.owns(id):
			out.append(id)
	return out

static func _to_market(app, root: Node, text: String, tab_id: String, key: String) -> void:
	# a way from the Armory to what the Market has (0.31.204)
	var b := UI2.button(root, text, "purple", func():
		app.sfx("tab")
		app.open_market(tab_id), key, 13, 38.0, 12.0, UI2.icon_path("stall"))
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

static func _armory_empty(root: Node, icon: String, head: String, line: String) -> void:
	var box := UI2.frame(root, "night", 16, 18.0, "gold")
	box.add_theme_constant_override("separation", 6)
	var ic := UI2.img(box, UI2.icon_path(icon), 56.0)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UI2.center(UI2.text(box, head, 20, Color.WHITE))
	var l := UI2.center(UI2.body(box, line, 12, UI2.SOFT))
	l.custom_minimum_size.x = 10

static func armory_outfits(app, root: VBoxContainer, outfits: Array) -> void:
	# 0.31.204: the outfits you own, his heroes' order -- WEAR / WORN on each (tap WORN: his own look again); tap the
	# picture: his window in it
	var p = app.profile
	var more := Eco.SKINS.size() - outfits.size()
	if outfits.is_empty():
		_armory_empty(root, "helmet", "NO OUTFITS YET", "A whole new look and weapon for a hero -- the Market has them, and a few are on sale this week.")
		_to_market(app, root, "BROWSE OUTFITS IN THE MARKET  ▸", "outfits", "armory_to_outfits")
		return
	var worn := 0
	for id in outfits:
		if p.worn_skin(str(Eco.SKINS[id].hero)) == str(id):
			worn += 1
	UI2.center(UI2.body(root, "%d yours  ·  %d worn  ·  tap WORN for his own look again" % [outfits.size(), worn], 11, UI2.SOFT))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 12)
	root.add_child(grid)
	for id in outfits:
		outfit_card(app, grid, str(id), true)
	if outfits.size() % 3 != 0:
		for i in 3 - outfits.size() % 3:
			var gap := Control.new()
			UI.grow(gap)
			grid.add_child(gap)
	if more > 0:
		_to_market(app, root, "%d MORE IN THE MARKET  ▸" % more, "outfits", "armory_to_outfits")

static func armory_titles(app, root: VBoxContainer, titles: Array) -> void:
	# 0.31.204: NO TITLE, then every title you've earned (EQUIP / WORN); the ones still to earn aren't shown -- how many
	var p = app.profile
	UI2.divider(root, "TITLES", 20, "shown next to your name")
	var none := UI2.frame(root, "night", 10, 14.0, "gold")
	var nr := UI.row(none, 8)
	UI.grow(UI2.text(nr, "NO TITLE", 15, Color.WHITE))
	var ne := UI2.button(nr, "EQUIPPED" if str(p.d.title) == "" else "EQUIP", "grey" if str(p.d.title) == "" else "blue", func():
		p.unequip("", "title")
		app.rebuild(), "equip_default_title", 13, 34.0, 11.0)
	ne.disabled = str(p.d.title) == ""
	ne.custom_minimum_size.x = 104
	for id in titles:
		locker_row(app, root, str(id))
	var left := 0
	for id in Eco.TITLE_GOALS:
		if not p.owns(id) and not Eco.retired(Eco.TITLE_GOALS[id]):
			left += 1
	for id in Eco.PRIZE_TITLES:
		if not p.owns(id):
			left += 1
	if titles.is_empty():
		_armory_empty(root, "scroll", "NO TITLES YET", "Titles are earned by playing -- win, take towers, climb the weekly leaderboard.")
	if left > 0:
		UI2.center(UI2.body(root, "%d more to earn by playing" % left, 11, UI2.SOFT))

# ---------------- the Locker's CHAMPIONS (0.31.187) ----------------
# The eighteen by role (League's six: a row of three each -- the class, its upgrade, the new hero), each a card: his own
# place painted behind him (Champions.card_art), him in the skin he wears, his name and class, and where he stands with
# you: yours (a tick), FREE this week, NEW at his launch price, or his price and a padlock; ◆ when you hold his shard, and
# how many skins he has. Tap: his window (champion_window.gd).
const ROLE_ORDER := ["tank", "fighter", "assassin", "mage", "marksman", "support"]

static func locker_champions(app, root: VBoxContainer) -> void:
	# 0.31.204: the Armory's HEROES -- the heroes you own, by role (a role with none of yours left out); the ones you
	# don't are in the Market's HEROES (a way there under them). 0.31.205 (Kevin: "Make the heros that are free for the
	# week show up in players armory"): and this week's free ones among them, FREE THIS WEEK on their cards (yours to
	# play until Monday; to keep, the Market)
	var p = app.profile
	var Kits = load("res://scripts/siege/moba_kits.gd")          # (loaded here, not at boot: the 5v5's)
	var order: Array = Champions.ORDER
	var mine: Array = order.filter(func(h): return p.owns_hero(str(h)))
	var free: Array = order.filter(func(h): return not p.owns_hero(str(h)) and p.can_play_hero(str(h)))
	var shown: Array = order.filter(func(h): return p.can_play_hero(str(h)))
	var top := UI2.center(UI2.body(root, "%d of %d heroes yours%s  ·  tap one for his story, his outfits and a closer look" % [mine.size(), order.size(),
		("  ·  %d free this week" % free.size()) if not free.is_empty() else ""], 11, UI2.SOFT))
	top.custom_minimum_size.x = 10
	var inv := ""
	if int(p.d.get("tokens", 0)) > 0:
		inv = "HERO TOKEN x%d" % int(p.d.tokens)
	var nsh := (p.d.get("shards", []) as Array).size()
	if nsh > 0:
		inv += ("  ·  " if inv != "" else "") + "◆ SHARD%s %d" % ["S" if nsh > 1 else "", nsh]
	if inv != "":
		var ic := UI2.chip(root, inv + "  ·  use them in the Market", Color("#173a1e"), Color("#c9f7bd"), Color("#6be07c"))
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for role in ROLE_ORDER:
		var hs: Array = shown.filter(func(h): return Kits.role_of(str(h)) == role)
		if hs.is_empty():
			continue
		var rh := HBoxContainer.new()
		rh.add_theme_constant_override("separation", 8)
		root.add_child(rh)
		var bp := "res://assets/ui/roles/%s.png" % role
		if ResourceLoader.exists(bp):
			var bi := UI2.img(rh, bp, 30.0)
			bi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var rt := UI2.text(rh, str(Kits.ROLE_NAMES.get(role, role)), 19, UI2.GOLD, UI2.INK, 5)
		rt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var rs := UI2.body(rh, str(Kits.ROLE_TEXT.get(role, "")), 10, UI2.SOFT, true)
		rs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rs.custom_minimum_size.x = 10
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		root.add_child(grid)
		for hid in hs:
			champion_card(app, grid, str(hid))
		if hs.size() < 3:                                  # (keep the cards a third wide)
			for i in 3 - hs.size():
				var gap := Control.new()
				gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				grid.add_child(gap)
	var more := order.size() - mine.size()
	if more > 0:
		_to_market(app, root, "%d MORE HERO%s IN THE MARKET  ▸" % [more, "" if more == 1 else "ES"], "heroes", "armory_to_heroes")

static func champion_card(app, grid: Node, hid: String) -> Button:
	var p = app.profile
	var acc: Color = Champions.accent(hid)
	var owned: bool = p.owns_hero(hid)
	var plays: bool = p.can_play_hero(hid)
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	for st_name in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st_name, StyleBoxEmpty.new())
	b.custom_minimum_size = Vector2(0, 196)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.set_meta("action_key", "champ_" + hid)
	b.pressed.connect(func(): app.open_champion(hid, "__worn", true))     # (0.31.204: the Armory's -- his outfits you own)
	grid.add_child(b)
	# the card: his place (cover), clipped to the rounded frame, darker toward the bottom for the name
	var card := Panel.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var sb := StyleBoxFlat.new()
	sb.bg_color = acc.darkened(0.8)
	sb.set_corner_radius_all(14)
	card.add_theme_stylebox_override("panel", sb)
	b.add_child(card)
	var art := TextureRect.new()
	var ap := Champions.card_art(hid)
	art.texture = load(ap) if ResourceLoader.exists(ap) else null
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not plays:
		art.modulate = Color(0.62, 0.62, 0.7)
	card.add_child(art)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.1), Color(acc.darkened(0.85), 0.95)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 4
	gt.height = 64
	gt.fill_to = Vector2(0, 1)
	var shade := TextureRect.new()
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(shade)
	# him, in the skin he wears
	var worn: String = p.worn_skin(hid)
	var pp := ("res://assets/ui/skins/%s.png" % worn) if worn != "" else ("res://assets/ui/skins/default_%s.png" % hid)
	var por := TextureRect.new()
	por.texture = load(pp) if ResourceLoader.exists(pp) else null
	por.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	por.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	por.anchor_right = 1.0
	por.offset_left = 4
	por.offset_right = -4
	por.offset_top = 22
	por.offset_bottom = 142
	por.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not plays:
		por.modulate = Color(0.7, 0.7, 0.78)
	card.add_child(por)
	var rim := Panel.new()
	var rs := StyleBoxFlat.new()
	rs.draw_center = false
	rs.border_color = acc if owned else Color(acc.darkened(0.25), 0.8)
	rs.set_border_width_all(3 if owned else 2)
	rs.set_corner_radius_all(14)
	rim.add_theme_stylebox_override("panel", rs)
	rim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(rim)
	# his name and class
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.anchor_top = 1.0
	v.anchor_bottom = 1.0
	v.anchor_right = 1.0
	v.offset_top = -56
	v.offset_bottom = -6
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var nl := UI2.text(v, Champions.short_of(hid).to_upper(), 17, Color.WHITE, acc.darkened(0.75), 5)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var cl := UI2.body(v, str(Eco.SKIN_HEROES.get(hid, hid)).to_upper(), 9, acc.lightened(0.5), false)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# where he stands with you
	var st := HBoxContainer.new()
	st.add_theme_constant_override("separation", 3)
	st.alignment = BoxContainer.ALIGNMENT_CENTER
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(st)
	# (0.31.204: the Armory has only yours -- the outfit he wears; 0.31.187-0.31.203 YOURS, or his price and a padlock)
	var wk: String = p.worn_skin(hid)
	if not owned and plays:                          # 0.31.205: this week's free one
		UI2.body(st, "FREE THIS WEEK", 9, Color("#9dff8a"), false)
	else:
		UI2.body(st, (str(Eco.SKINS[wk].set).to_upper() if wk != "" else "ORIGINAL LOOK"), 9, Color("#e8ccff") if wk != "" else Color(1, 1, 1, 0.7), false)
	var chips := VBoxContainer.new()                # (stacked down the left: the skins' count is on the right)
	chips.add_theme_constant_override("separation", 3)
	chips.position = Vector2(6, 6)
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(chips)
	if not owned and plays:
		UI2.chip(chips, "FREE", Color("#2f8a3e"), Color.WHITE, Color("#0a2006"))
	if Eco.launching(hid, p.now()):
		UI2.chip(chips, "NEW", Color("#d9682a"), Color.WHITE, Color("#3a1402"))
	if not owned and p.shards_of(hid) > 0:
		UI2.chip(chips, "◆", Color("#173a1e"), Color("#9dff8a"), Color("#6be07c"))
	var nsk := Eco.skins_of(hid).filter(func(id): return p.owns_skin(str(id))).size()     # (0.31.204: the ones you own)
	if nsk > 0:
		var sc := UI2.chip(b, "%d OUTFIT%s" % [nsk, "" if nsk == 1 else "S"], Color(0.05, 0.03, 0.12, 0.8), Color("#e8ccff"), Color("#c47bff"))
		sc.anchor_left = 1.0
		sc.anchor_right = 1.0
		sc.offset_left = -62
		sc.offset_right = -6
		sc.offset_top = 6
		sc.offset_bottom = 22
		sc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b

# + / − zoom buttons and the hint over an interactive showcase (the pass item view, 0.31.48; the locker, 0.31.64)
static func zoom_controls(stage: Control, sh, prefix: String) -> void:
	var zc := VBoxContainer.new()
	zc.add_theme_constant_override("separation", 10)
	zc.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	zc.offset_left = -58
	zc.offset_right = -12
	zc.offset_top = -50
	zc.offset_bottom = 50
	stage.add_child(zc)
	for zb in [["+", 1.3, prefix + "_zoom_in"], ["−", 1.0 / 1.3, prefix + "_zoom_out"]]:
		var zf: float = zb[1]
		var b := UI2.button(zc, str(zb[0]), "blue", func(): sh.zoom_by(zf), str(zb[2]), 24, 44.0, 22.0)
		b.custom_minimum_size = Vector2(44, 44)
		b.add_theme_font_override("font", UI.HEAVY_FONT)
	var hint := UI2.chip(stage, "DRAG TO TURN  ·  PINCH TO ZOOM", Color(0.02, 0.03, 0.1, 0.75), Color(1, 1, 1, 0.85), Color(UI2.GOLD, 0.5))
	hint.anchor_left = 0.5
	hint.anchor_right = 0.5
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = -100
	hint.offset_right = 100
	hint.offset_top = -30
	hint.offset_bottom = -10

static func locker_row(app, root: Node, id: String) -> void:
	# A title card (0.31.87, Kevin picked the looks): the rarity's panel and rim, the name exactly as it shows over the
	# head (punctuated, the title in its rarity's colour), what earns it and how far along it is; EQUIP once earned.
	var p = app.profile
	var it := Eco.item(id)
	var rar := str(it.rarity)
	var goal: Dictionary = Eco.TITLE_GOALS.get(id, Eco.PRIZE_TITLES.get(id, {}))     # (0.31.120: the leaderboard's titles)
	var c := UI2.frame(root, _rar_panel(rar), 8, 16.0, _rar_rim(rar), {"pattern_mix": 0.0})
	var pc := c.get_parent() as Control
	if rar == "legendary":
		UI2.sweep(pc, 2.6, 60.0, 0.3)
	var r := UI.row(c, 10)
	var ic := Control.new()
	ic.custom_minimum_size = Vector2(48, 48)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(ic)
	if rar in ["epic", "legendary"]:
		var rays := UI2.rays(ic, 80.0, Color(1, 0.85, 0.45) if rar == "legendary" else Color(0.8, 0.6, 1.0), 14.0, 0.5)
		rays.position = Vector2(24, 24) - Vector2(40, 40)
	var icn := UI2.icon(ic, {"common": "scroll", "rare": "banner", "epic": "trophy", "legendary": "crown"}.get(rar, "scroll"), 46.0)
	icn.position = Vector2(1, 1)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	UI.grow(v)
	r.add_child(v)
	var owned: bool = p.owns(id)
	var top := UI.row(v, 6)
	UI2.chip(top, rar.to_upper(), Color(str(Eco.RARITY_COLOR.get(rar, "#b8c4c9"))), Color("#120a02"))
	UI2.body(top, "EARNED" if owned else "LOCKED", 10, Color("#8cf0a8") if owned else Color(1, 1, 1, 0.6), false)
	var nm := HBoxContainer.new()
	nm.add_theme_constant_override("separation", 0)
	v.add_child(nm)
	for part in Net.title_parts(str(p.d.name), id):
		UI2.text(nm, str(part[0]), 17, _rar_tint(rar).lightened(0.25) if part[1] else Color.WHITE, Color("#120a02"), 5)
	UI2.body(v, str(goal.get("task", "")), 11, Color(1, 1, 1, 0.82), false)
	var n: int = int(goal.get("n", 1))
	var have: int = n if owned else (0 if Eco.PRIZE_TITLES.has(id) else mini(n, p.title_progress(id)))
	var pr := UI.row(v, 6)
	var gold := rar == "legendary"
	UI2.bar(pr, float(have), float(n), Color("#fff3ad") if gold else Color("#b6f3ff"), Color("#f0a024") if gold else Color("#36b9ea"), 10.0)
	UI2.body(pr, "%s / %s" % [_thousands(have), _thousands(n)], 11, Color.WHITE, false)
	if owned:
		var eq: bool = is_equipped(p, id)
		var b := UI2.button(r, "WORN" if eq else "EQUIP", "grey" if eq else "green", func(): equip(app, id), "equip_" + id, 13, 40.0, 12.0)
		b.disabled = eq
		b.custom_minimum_size.x = 74
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER

static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out

# ---------------- SETTINGS ----------------
static func play_games_card(app, root: VBoxContainer) -> void:
	if Platform.is_ios():
		game_center_card(app, root)                       # 0.31.130
		return
	var gp := UI2.frame(root, "night", 12, 18.0, "gold")
	UI2.divider(gp, "GOOGLE PLAY", 20)
	var pg = app.play_games
	var st := str(pg.state) if pg != null else "off"
	var line := ""
	match st:
		"off":
			line = "Sign in with Google Play to keep your progress in your Google account and take it to a new phone. Available in the Google Play version of Fatebound."
		"out":
			line = "Not signed in. Sign in to keep your progress in your Google account and take it to a new phone."
		"signing":
			line = "Signing in to Google Play..."
		"checking":
			line = "Checking your Google Play save..."
		"synced":
			var who := str(pg.player)
			line = "Signed in%s. Your progress is backed up to your Google account%s." % [(" as " + who) if who != "" else "", _ago(app, int(pg.last_backup()))]
		"ask":
			line = "Google Play has different progress from this phone. Choose which one to keep."
		"error":
			line = (str(pg.why) if str(pg.why) != "" else "Couldn't reach Google Play saves") + ". Your progress on this phone is safe."
	UI2.body(gp, line, 12, UI2.SOFT)
	match st:
		"out":
			UI2.button(gp, "SIGN IN WITH GOOGLE PLAY", "blue", func():
				app.sfx("confirm")
				pg.sign_in(), "play_sign_in", 15, 44.0)
		"synced":
			UI2.button(gp, "BACK UP NOW", "green", func():
				app.sfx("confirm")
				pg.back_up_now(), "play_backup", 15, 44.0)
			UI2.button(gp, "ACHIEVEMENTS", "gold", func():                # 0.31.119: Google Play Games' own screen
				app.sfx("menuOpen")
				pg.show_achievements(), "play_achievements", 15, 44.0)
		"ask":
			UI2.button(gp, "CHOOSE", "gold", func():
				app.ask_cloud(), "play_choose", 15, 44.0)
		"error":
			UI2.button(gp, "TRY AGAIN", "blue", func():
				app.sfx("confirm")
				pg.back_up_now(), "play_retry", 15, 44.0)

static func game_center_card(app, root: VBoxContainer) -> void:
	# 0.31.130 (the iOS port): Game Center -- signed in (achievements) or where to sign in. Apple allows no in-app sign-in
	# once a player has declined, so it points to iOS Settings. The progress itself is the Fatebound account's.
	var gp := UI2.frame(root, "night", 12, 18.0, "gold")
	UI2.divider(gp, "GAME CENTER", 20)
	var pg = app.play_games
	var st := str(pg.state) if pg != null else "off"
	var line := ""
	match st:
		"off":
			line = "Game Center isn't available in this build."
		"signing":
			line = "Signing in to Game Center..."
		"synced":
			var who := str(pg.player)
			line = "Game Center: signed in%s. Achievements are kept in Game Center." % ((" as " + who) if who != "" else "")
		_:
			line = "Not signed in. Sign in from iOS Settings > Game Center to earn achievements."
	UI2.body(gp, line, 12, UI2.SOFT)
	if st == "synced":
		UI2.button(gp, "ACHIEVEMENTS", "gold", func():                    # Apple's own screen
			app.sfx("menuOpen")
			pg.show_achievements(), "gc_achievements", 15, 44.0)

static func account_card(app, root: VBoxContainer) -> void:
	# 0.31.132 (the iOS port, IOS_PORT_SPEC_FOR_CLAUDE.md §4, §6): the Fatebound account -- the progress itself -- moved
	# between phones with a one-time code (Android and iPhone alike), and deleted from here (App Store 5.1.1(v)).
	var al = app.get("account_link")
	if al == null:
		return
	var ac := UI2.frame(root, "night", 12, 18.0, "gold")
	UI2.divider(ac, "ACCOUNT", 20)
	var has: bool = al.has_account()
	UI2.body(ac, ("Your progress is kept in your Fatebound account on our server. Take it to another phone, Android or "
		+ "iPhone, with a one-time code.") if has else "Your account is made the first time the game reaches our server.", 12, UI2.SOFT)
	var mv := UI2.button(ac, "MOVE TO ANOTHER PHONE", "blue", func():
		app.sfx("confirm")
		app.show_move_code(), "move_new", 15, 44.0)
	mv.disabled = not has
	UI2.button(ac, "ENTER A CODE", "green", func():
		app.sfx("confirm")
		app.enter_move_code(), "move_enter", 15, 44.0)
	var dl := UI2.button(ac, "DELETE ACCOUNT", "red", func():
		app.ask_delete_account(), "account_delete", 13, 38.0)
	dl.disabled = not has

static func _ago(app, at: int) -> String:
	if at <= 0:
		return ""
	var s: int = maxi(0, int(app.profile.now()) - at)
	if s < 60:
		return " (just now)"
	if s < 3600:
		return " (%d min ago)" % (s / 60)
	if s < 86400:
		return " (%d h ago)" % (s / 3600)
	return " (%d days ago)" % (s / 86400)

static func settings(app, root: VBoxContainer) -> void:
	# 0.31.79: a wooden sign with a turning gear, the profile on parchment, the career in tiles with the 3D icons, then
	# sound, graphics, the old game's progress and help.
	var p = app.profile
	var d: Dictionary = p.d
	var sign := Control.new()
	sign.custom_minimum_size = Vector2(0, 66)
	root.add_child(sign)
	var board := HBoxContainer.new()
	board.alignment = BoxContainer.ALIGNMENT_CENTER
	board.add_theme_constant_override("separation", 10)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sign.add_child(board)
	sign.resized.connect(func():
		board.size = Vector2(260, 60)
		board.position = Vector2((sign.size.x - 260.0) * 0.5, 2))
	UI2.plate(board, "wood", 14.0, "gold", {"rim": 4.0})
	var gear := UI2.icon(board, "gear", 42.0)
	gear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UI2.spin(gear, 14.0)
	UI2.text(board, "SETTINGS", 30, UI2.GOLD).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Profile (parchment)
	var prof := UI2.frame(root, "parch", 12, 16.0, "brown")
	var ink := Color("#3b2412")
	var top := UI.row(prof, 10)
	var shc := Control.new()
	shc.custom_minimum_size = Vector2(48, 54)
	top.add_child(shc)
	var sht := TextureRect.new()
	sht.texture = UI2.tex(UI2.V2 + "shield.svg")
	sht.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sht.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sht.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shc.add_child(sht)
	var lvl := UI2.text(shc, str(int(d.level)), 22, Color.WHITE, Color("#0e1433"), 5)
	lvl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lvl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lvl.offset_bottom = -6
	var nv := VBoxContainer.new()
	UI.grow(nv)
	top.add_child(nv)
	var yl := UI.label(nv, "YOUR NAME", 10, Color("#7a5530"), UI.HEAVY_FONT)
	yl.autowrap_mode = TextServer.AUTOWRAP_OFF
	var nr := UI.row(nv, 8)
	var name_edit := LineEdit.new()
	name_edit.text = str(d.name)
	name_edit.max_length = 24          # capped to 16 after trimming spaces (see SAVE)
	name_edit.placeholder_text = "Your name"
	name_edit.add_theme_font_override("font", UI.HEAVY_FONT)
	name_edit.add_theme_font_size_override("font_size", 16)
	name_edit.add_theme_color_override("font_color", ink)
	var es := StyleBoxFlat.new()
	es.bg_color = Color("#fffaf0")
	es.border_color = Color("#5d3a1c")
	es.set_border_width_all(3)
	es.set_corner_radius_all(10)
	es.content_margin_left = 10
	es.content_margin_right = 10
	es.content_margin_top = 6
	es.content_margin_bottom = 6
	name_edit.add_theme_stylebox_override("normal", es)
	name_edit.add_theme_stylebox_override("focus", es)
	UI.grow(name_edit)
	nr.add_child(name_edit)
	var sv := UI2.button(nr, "SAVE", "green", func():
		var nm := name_edit.text.strip_edges().left(16)
		if nm == "":
			nm = "Player"
		p.set_name(nm)                             # (0.31.108: an op, so the server has it too)
		app.sfx("confirm")
		app.toast("Name saved", UI.CYAN)
		app.refresh_top(), "save_name", 16, 40.0, 11.0)
	sv.custom_minimum_size.x = 76
	var xr := UI.row(prof, 8)
	var xl := UI.label(xr, "LEVEL %d" % int(d.level), 11, ink, UI.HEAVY_FONT)
	xl.autowrap_mode = TextServer.AUTOWRAP_OFF
	UI2.bar(xr, int(d.xp), Eco.level_xp(int(d.level)), Color("#b6f3ff"), Color("#2b8fd6"), 12.0)
	var xv := UI.label(xr, "%d / %d XP" % [int(d.xp), Eco.level_xp(int(d.level))], 11, ink, UI.HEAVY_FONT)
	xv.autowrap_mode = TextServer.AUTOWRAP_OFF
	# Google Play (0.31.102, Kevin: "Google play account linking to the game"): sign in, and the progress kept there
	play_games_card(app, root)
	account_card(app, root)                               # 0.31.132: the account between phones
	# Career
	var car := UI2.frame(root, "royal", 12, 18.0, "gold")
	UI2.divider(car, "CAREER", 20)
	var st: Dictionary = d.stats
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	car.add_child(grid)
	var wins := int(st.wins)
	var matches := int(st.matches)
	# (0.31.164, 5v5 only: towers, last hits and jungle camps where King rescues, gathering and fish were)
	var tiles := [["swords", UI.compact(matches), "MATCHES"], ["trophy", UI.compact(wins), "WINS"], ["castle", UI.compact(int(st.get("towers", 0))), "TOWERS"],
		["skull", UI.compact(int(st.kills)), "KNOCKOUTS"], ["anvil", UI.compact(int(st.gates) * 100), "TOWER DMG"], ["helmet", UI.compact(int(st.get("lh", 0))), "LAST HITS"],
		["horn", UI.compact(int(st.get("camps", 0))), "CAMPS"], ["banner", ("%d%%" % int(round(100.0 * wins / matches))) if matches > 0 else "--", "WIN RATE"]]
	var i := 0
	for tdef in tiles:
		var tc := VBoxContainer.new()
		tc.add_theme_constant_override("separation", 0)
		tc.alignment = BoxContainer.ALIGNMENT_CENTER
		tc.custom_minimum_size = Vector2(0, 96)
		UI.grow(tc)
		grid.add_child(tc)
		UI2.plate(tc, "glass", 14.0)
		var ic := UI2.icon(tc, str(tdef[0]), 42.0)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		UI2.bob(ic, 2.5, 1.3 + (i % 3) * 0.2, i * 0.15)
		UI2.center(UI2.text(tc, str(tdef[1]), 19, Color.WHITE))
		UI2.center(UI2.body(tc, str(tdef[2]), 9, UI2.MUTED, false))
		i += 1
	# Sound
	var au := UI2.frame(root, "night", 12, 18.0, "gold")
	UI2.divider(au, "SOUND", 20)
	for pair in [["master", "Master"], ["sfx", "Effects"], ["music", "Music"]]:
		var key: String = pair[0]
		var row := UI.row(au, 10)
		var ll := UI2.text(row, str(pair[1]).to_upper(), 14, Color.WHITE)
		ll.custom_minimum_size.x = 76
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = float(d.settings.get(key, 1.0))       # 0.31.110 (Kevin): every slider at 100% by default
		sl.set_meta("action_key", "slider_" + key)
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UI2.style_slider(sl)
		UI.grow(sl)
		row.add_child(sl)
		var pv := UI2.text(row, "%d%%" % int(round(sl.value * 100)), 14, UI2.GOLD)
		pv.custom_minimum_size.x = 44
		pv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		sl.value_changed.connect(func(v: float):
			pv.text = "%d%%" % int(round(v * 100))
			d.settings[key] = v
			p.save()
			app._apply_audio()
			app.sfx("slider"))                 # 0.31.110: a tiny tick a step, at the new level
	# 0.31.120 (Kevin: phone vibration): a buzz when you're hit, knock someone out, fall, or a King is rescued
	UI2.toggle(au, "Vibration", "A buzz each time you knock out an enemy", bool(d.settings.get("vibrate", true)), "vibrate", func(on: bool):
		app.sfx("toggle")
		d.settings["vibrate"] = on
		p.save()
		if on:
			Input.vibrate_handheld(60, 0.7))
	# Social (0.31.111)
	var sx := UI2.frame(root, "night", 12, 18.0, "gold")
	UI2.divider(sx, "SOCIAL", 20)
	UI2.toggle(sx, "Global chat", "Everyone online; friends and party chat stay on", bool(d.settings.get("chat_global", true)), "chat_global", func(on: bool):
		app.sfx("toggle")
		d.settings.chat_global = on
		p.save()
		if app.social != null:
			app.social.set_show_global(on))
	var soc2 = app.get("social")
	if soc2 != null and soc2.online():
		var fc := UI.row(sx, 8)
		var fcl := UI2.body(fc, "Your friend code: %s" % soc2.code_of(str(soc2.me.get("pid", ""))), 13, UI2.SOFT, false)
		fcl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fcl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fb := UI2.button(fc, "FRIENDS", "blue", func():
			app.sfx("menuOpen")
			app.open_friends(), "settings_friends", 13, 36.0, 11.0)
		fb.custom_minimum_size.x = 100
	UI2.body(sx, "Tap a name in the chat to add a friend, block or report them.", 11, UI2.MUTED)
	# 0.31.124 (Kevin: "Add the discord link to the game" + "give a reward for joining the discord")
	var cx := UI2.frame(root, "night", 12, 18.0, "gold")
	cx.name = "CommunityCard"
	UI2.divider(cx, "COMMUNITY", 20)
	var claimed := bool(d.get("discord", false))
	UI2.body(cx, "Join the Fatebound Discord: news, updates, events and other players to team up with." +
		("" if claimed else " Joining gives you %d gems, once." % Eco.DISCORD_GEMS), 12, UI2.SOFT)
	var dlabel := "JOIN OUR DISCORD" if claimed else "JOIN OUR DISCORD  ·  +%d GEMS" % Eco.DISCORD_GEMS
	UI2.button(cx, dlabel, "discord", func(): discord_press(app), "discord", 15, 46.0)
	# 0.31.118 (Kevin's analytics spec): usage statistics to our own server, on by default, off here
	var px := UI2.frame(root, "night", 12, 18.0, "gold")
	UI2.divider(px, "PRIVACY", 20)
	UI2.toggle(px, "Share anonymous usage stats", "Sessions, matches and menu use -- never your name or chat", bool(d.settings.get("analytics", true)), "analytics", func(on: bool):
		app.sfx("toggle")
		d.settings.analytics = on
		p.save()
		if app.get("analytics") != null:
			app.analytics.set_enabled(on))
	UI2.body(px, "Only to Fatebound's own server, tied to your game account's random id. Kept 90 days, never sold or shared.", 11, UI2.MUTED)
	# 0.31.119: notifications (the Play build's plugin; the preview APK has none)
	var nx := UI2.frame(root, "night", 12, 18.0, "gold")
	UI2.divider(nx, "NOTIFICATIONS", 20)
	var nt: Variant = app.get("notify")
	var can_notify: bool = nt != null and nt.available()
	var ntb := UI2.toggle(nx, "Chest ready", "A notification when a chest has finished unlocking" if can_notify else "Not in this version of the app",
		bool(d.settings.get("notify", true)) and can_notify, "notify", func(on: bool):
		app.sfx("toggle")
		d.settings.notify = on
		d.settings.notify_asked = true
		p.save()
		if on and nt != null and not nt.has_permission():
			nt.request_permission())
	ntb.disabled = not can_notify
	if not can_notify:
		ntb.modulate = Color(1, 1, 1, 0.45)
	# Graphics
	var gx := UI2.frame(root, "night", 12, 18.0, "gold")
	UI2.divider(gx, "GRAPHICS", 20)
	# (0.31.163, Kevin: "Remove both": no High-quality graphics toggle -- always on, siege_app ignores a saved "off")
	UI2.toggle(gx, "Reduce effects", "Smoother on older phones", bool(d.settings.get("reduce_motion", false)), "reduce_motion", func(on: bool):
		app.sfx("toggle")
		d.settings.reduce_motion = on
		p.save())
	# (0.31.123, Kevin: "Remove the progress from old version in the settings since Google play saves progress now":
	# the old version's paste-in import card is gone; a legacy save on the phone is still carried over by itself, once --
	# Profile.import_legacy at first launch)
	# Help
	# 0.31.120 (Kevin: SEND TO DEVELOPER): the log straight to the developer's server, asked every time
	UI2.button(root, "SEND TO DEVELOPER", "orange", func(): app.open_send_diag(), "send_diag", 15, 44.0)
	var help := HBoxContainer.new()
	help.add_theme_constant_override("separation", 10)
	root.add_child(help)
	if Diag.has_logs():
		UI.grow(UI2.button(help, "COPY DIAGNOSTICS", "blue", func():
			DisplayServer.clipboard_set(Diag.read_logs())
			app.toast("Diagnostics copied", UI.CYAN), "copy_diag", 13, 40.0))
	UI.grow(UI2.button(help, "PRIVACY POLICY", "blue", func(): OS.shell_open(PRIVACY_URL), "privacy", 13, 40.0))
	# (0.31.112-0.31.163: HOW TO PLAY (TUTORIAL) -- Siege's walkthrough; gone with Siege, 0.31.164.) 0.31.181: the 5v5's
	UI2.button(root, "HOW TO PLAY (TUTORIAL)", "blue", func():
		app.sfx("confirm")
		app.start_tutorial(), "settings_tutorial", 14, 44.0)
	var ver := UI2.body(root, "Fatebound %s" % Diag.BUILD, 11, UI2.MUTED)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

# ---------------- QUESTS (0.31.97, Kevin: "Build the quest system and I want quests for each class") ----------------
# Every class has one quest (Eco.QUESTS): three steps claimed in order (0.31.188: the last pays gems and a Royal chest --
# it gave the class's legendary weapon). The class picker shows a badge where a step is ready and a tick where the quest
# is done; the hero stands in his own place in the outfit he wears (turn and zoom him); each step shows its task, how far
# along it is, what it pays and CLAIM when it can be claimed.
const QUEST_ICON := "res://assets/ui/v2/icons/quest.png"

static func quest_icon_name() -> String:
	return "quest" if ResourceLoader.exists(QUEST_ICON) else "crown"

static func _reward_chips(parent: Node, r: Dictionary, ink := Color.WHITE) -> HBoxContainer:
	# the reward of a quest step as small pictures with their amounts
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var parts := []
	for k in ["gold", "gems", "chest"]:
		if r.has(k):
			parts.append({k: r[k]})
	for part in parts:
		var rt := reward_text(part)
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 3)
		row.add_child(cell)
		if str(rt[3]) != "":
			UI2.img(cell, str(rt[3]), 22.0).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var t := str(rt[1])
		if part.has("gold") or part.has("gems"):
			t = "+%d" % int(part.values()[0])
		UI2.body(cell, t, 11, rt[2] if ink == Color.WHITE else ink, false).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return row

static func quest_first(p) -> String:
	# the class to open the Quests screen on: one with a step ready, else the one played most, else the Knight
	for cls in Eco.QUESTS:
		if p.quest_ready(cls) and str(cls) != "worker":
			return str(cls)
	var best := "knight"
	var most := 0
	for cls in Eco.QUESTS:
		if str(cls) == "worker":
			continue
		var n := int(p.d.stats.get(Eco.quest_key(cls, "matches"), 0))
		if n > most:
			most = n
			best = str(cls)
	return best

static func claim_quest(app, cls: String) -> void:
	var p = app.profile
	var res: Dictionary = p.claim_quest(cls)
	if not bool(res.get("ok", false)):
		return
	var last: bool = int(res.step) + 1 >= (Eco.QUESTS[cls].steps as Array).size()
	app.sfx("revealLegendary" if last else "claim")      # 0.31.110: the quest's end gets the golden choir
	app.refresh_top()
	var bits := []
	for k in ["gold", "gems"]:
		if int(res.reward.get(k, 0)) > 0:
			bits.append("+%d %s" % [int(res.reward[k]), {"gold": "gold", "gems": "gems"}[k]])
	if res.reward.has("chest"):
		bits.append("a %s" % str(Eco.CHESTS[str(res.reward.chest)].name))
	app.toast(("Quest complete! %s" if last else "Quest step %d done: %s" % [int(res.step) + 1, "%s"]) % ", ".join(bits), UI.GOLD)
	app.rebuild()

static func quests(app, root: VBoxContainer) -> void:
	var p = app.profile
	# the sign
	var sign := Control.new()
	sign.custom_minimum_size = Vector2(0, 66)
	root.add_child(sign)
	var board := HBoxContainer.new()
	board.alignment = BoxContainer.ALIGNMENT_CENTER
	board.add_theme_constant_override("separation", 10)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sign.add_child(board)
	sign.resized.connect(func():
		board.size = Vector2(230, 60)
		board.position = Vector2((sign.size.x - 230.0) * 0.5, 2))
	UI2.plate(board, "wood", 14.0, "gold", {"rim": 4.0})
	UI2.icon(board, quest_icon_name(), 46.0).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UI2.text(board, "QUESTS", 28, UI2.GOLD).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var back := UI2.button(sign, "", "ghost", func():
		app.sfx("menuClose")
		app.show_tab("home"), "quests_back", 14, 40.0, 12.0)
	back.position = Vector2(0, 12)
	back.size = Vector2(46, 40)
	UI.icon(back, "home", 22, Color.WHITE).position = Vector2(12, 7)
	UI2.center(UI2.body(root, "Every class has a quest. Finish its three steps for gold, gems and a Royal chest.", 12, UI2.SOFT))
	# class picker: a badge where a step is ready, a tick where the quest is done
	var cls: String = app.quest_cls if Eco.QUESTS.has(str(app.quest_cls)) and str(app.quest_cls) != "worker" else quest_first(p)
	app.quest_cls = cls
	var rail := UI2.frame(root, "glass", 8, 18.0)
	for row_classes in [Eco.HERO_CLASSES, Eco.UP_CLASSES]:             # (0.31.164: no Worker -- Siege's)
		var rr := HBoxContainer.new()
		rr.alignment = BoxContainer.ALIGNMENT_CENTER
		rr.add_theme_constant_override("separation", 4)
		rail.add_child(rr)
		for c0 in row_classes:
			var c: String = c0
			var cb := _class_coin(rr, c, cls == c, "quest_" + c, func():
				app.quest_cls = c
				app.sfx("tap")
				app.rebuild(), "", 38.0)
			if p.quest_ready(c):
				UI2.badge(cb, "!", Vector2(2, -4))
			elif p.quest_done(c):
				var tick := UI2.chip(cb, "✔", Color("#2f9e55"), Color.WHITE, Color(1, 1, 1, 0.6))
				tick.position = Vector2(16, -4)
				tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var q: Dictionary = Eco.QUESTS[cls]
	var step: int = p.quest_step(cls)
	var done: bool = p.quest_done(cls)
	# the hero, in his own place (0.31.188; it was the hero holding the legendary)
	var hero := Control.new()
	hero.custom_minimum_size = Vector2(0, 300)
	root.add_child(hero)
	var stage := Control.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.offset_left = 5
	stage.offset_top = 5
	stage.offset_right = -5
	stage.offset_bottom = -5
	stage.clip_contents = true
	hero.add_child(stage)
	UI2.plate(hero, "ember", 22.0, "orange", {"rim": 4.0})
	var art := TextureRect.new()
	var ap := Champions.art(cls)
	art.texture = load(ap) if ResourceLoader.exists(ap) else null
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.offset_top = -110
	art.offset_bottom = 90
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(art)
	var sh := Showcase.new()
	sh.interactive = true
	sh.plinth = false
	sh.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(sh)
	sh.show_look(cls, p.look_for(cls))
	zoom_controls(stage, sh, "quests")
	if done:
		var tag := UI2.chip(stage, "QUEST COMPLETE", Color("#2f9e55"), Color.WHITE, Color(UI2.GOLD, 0.6))
		tag.position = Vector2(10, 8)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# the nameplate: who he is
	var np := UI2.frame(root, "ember", 8, 16.0, "orange")
	var nm := UI2.text(np, Champions.name_of(cls).to_upper(), 24, Color("#ffd27a"), Color("#3d1602"), 6)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI2.sweep(np.get_parent() as Control, 2.6, 60.0, 0.3)
	var sub := "%s  ·  QUEST %s" % [str(Eco.CLASS_NAMES[cls]).to_upper(), "COMPLETE" if done else "STEP %d OF %d" % [step + 1, q.steps.size()]]
	UI2.center(UI2.body(np, sub, 11, Color("#ffe7c8"), false))
	var note := Eco.quest_note(cls)
	if note != "":
		UI2.center(UI2.body(np, note, 10, Color(1, 1, 1, 0.7), false))
	# the steps
	for i in q.steps.size():
		quest_step_card(app, root, cls, i)

static func quest_step_card(app, root: Node, cls: String, i: int) -> void:
	var p = app.profile
	var q: Dictionary = Eco.QUESTS[cls]
	var s: Dictionary = q.steps[i]
	var step: int = p.quest_step(cls)
	var claimed := i < step
	var current := i == step
	var n := int(s.n)
	var have: int = n if claimed else mini(n, Eco.quest_progress(p.d.stats, cls, i))
	var ready: bool = current and have >= n
	var last: bool = i == q.steps.size() - 1
	var c := UI2.frame(root, "royal" if ready else ("ember" if last and not claimed else "night"), 8, 16.0,
		"gold" if ready else ("orange" if last else "silver"), {"pattern_mix": 0.0, "dim": 0.3 if claimed else 0.0})
	if ready:
		UI2.sweep(c.get_parent() as Control, 2.2, 60.0, 0.35)
	var r := UI.row(c, 10)
	# the step's number (a tick once claimed)
	var disc := Control.new()
	disc.custom_minimum_size = Vector2(40, 40)
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(disc)
	UI2.plate(disc, "royal" if not claimed else "night", 20.0, "gold" if (current or claimed) else "silver", {"rim": 2.0})
	var dl := UI2.text(disc, "✔" if claimed else str(i + 1), 18, UI2.CYAN if current else Color.WHITE, UI2.INK, 4)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	UI.grow(v)
	r.add_child(v)
	UI2.text(v, str(s.task), 14, Color.WHITE if not claimed else Color(1, 1, 1, 0.65), UI2.INK, 4).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var pr := UI.row(v, 6)
	var gold: bool = last
	UI2.bar(pr, float(have), float(n), Color("#fff3ad") if gold else Color("#b6f3ff"), Color("#f0a024") if gold else Color("#36b9ea"), 10.0)
	UI2.body(pr, "%s / %s" % [_thousands(have), _thousands(n)], 11, Color.WHITE, false)
	var rw := UI.row(v, 6)
	UI2.body(rw, "CLAIMED" if claimed else ("REWARD" if not last else "FINAL REWARD"), 9, Color("#8cf0a8") if claimed else Color(1, 1, 1, 0.6), false)
	_reward_chips(rw, Eco.quest_reward(cls, i))
	if ready:
		var b := UI2.button(r, "CLAIM", "gold", func(): claim_quest(app, cls), "quest_claim_" + cls, 14, 42.0, 12.0)
		b.custom_minimum_size.x = 80
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UI2.pulse(b, 0.03, 1.0)
	elif i > step:
		UI2.body(r, "after step %d" % (i), 10, Color(1, 1, 1, 0.5), false).size_flags_vertical = Control.SIZE_SHRINK_CENTER
