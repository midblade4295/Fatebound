extends RefCounted
# Screens for the Siege app shell. Each builds into `root` from app.profile; the shell rebuilds
# the current screen after every change (buy, claim, equip...).
const UI = preload("res://scripts/app/ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")
const ChestRow = preload("res://scripts/app/chest_row.gd")
const ChestOpen = preload("res://scripts/app/chest_open.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const Showcase = preload("res://scripts/app/showcase.gd")
const Diag = preload("res://scripts/siege/siege_diag.gd")

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
	match str(it.get("kind", "")):
		"title": return "title"
		"skin": return str(it.get("class", "skin"))
		"weapon": return str(it.get("class", "weapon"))
	return "star"

static func item_kind_text(it: Dictionary) -> String:
	var cls := str(Eco.CLASS_NAMES.get(str(it.get("class", "")), ""))
	var k := {"skin":"Skin", "weapon":"Weapon", "title":"Title"}.get(str(it.get("kind", "")), "") as String
	return (cls + " · " + k) if cls != "" else k

static func rarity(it: Dictionary) -> Color:
	return Color(str(Eco.RARITY_COLOR.get(str(it.get("rarity", "common")), "#b8c4c9")))

static func swatch(parent: Node, tex: Texture2D, edge: Color, px := 56, fallback := "", tint := Color.WHITE) -> void:
	# A rarity-framed tile showing a pre-rendered icon (or a procedural glyph if there is none).
	var box := PanelContainer.new()
	var sb := UI.card_style(Color(edge.r * 0.20, edge.g * 0.20, edge.b * 0.26, 0.92), 14, edge, false)
	sb.set_border_width_all(2)
	for side in ["left", "right", "top", "bottom"]:
		sb.set("content_margin_" + side, 3.0)
	box.add_theme_stylebox_override("panel", sb)
	box.custom_minimum_size = Vector2(px, px)
	parent.add_child(box)
	if tex != null:
		var t := TextureRect.new()
		t.texture = tex
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(t)
	else:
		var ic := UI.icon(box, fallback, px - 22, tint)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER

static func item_texture_path(id: String) -> String:
	match str(Eco.item(id).get("kind", "")):
		"skin": return "res://assets/ui/skins/%s.png" % id
		"weapon": return "res://assets/ui/icons/%s.png" % id
	return ""

static func item_swatch(parent: Node, id: String, px := 56) -> void:
	var it := Eco.item(id)
	var tp := item_texture_path(id)
	swatch(parent, UI.tex(tp) if tp != "" else null, rarity(it), px, item_icon(it), rarity(it).lightened(0.25))

static func chest_icon(kind: String) -> String:
	return UI2.V2 + "chests/%s_icon.png" % str({"wooden": "wood"}.get(kind, kind))

static func reward_text(r: Dictionary) -> Array:
	# -> [glyph kind, text, colour, texture path or ""]
	if r.has("chest"):                                   # (0.31.79: chests used to read "0 gold" here)
		var ck := str(r.chest)
		return ["chest", str(Eco.CHESTS.get(ck, {}).get("name", "Chest")), Color(str(Eco.CHESTS.get(ck, {}).get("color", "#ffcf4a"))), chest_icon(ck)]
	if r.has("item"):
		var it := Eco.item(str(r.item))
		return [item_icon(it), str(it.get("name", "?")), rarity(it), item_texture_path(str(r.item))]
	if r.has("gems"):
		return ["gem", "%d gems" % int(r.gems), UI.CYAN, "res://assets/ui/currency/gem.png"]
	var g := int(r.get("gold", 0))
	return ["coin", "%d gold" % g, UI.GOLD, "res://assets/ui/currency/%s.png" % ("coins_s" if g >= 300 else "coin")]

static func pack_list(app, root: Node) -> void:
	# 0.31.79: the Arsenals, two to a row: the items fanned out, the name, what's in it, a gem button (the price covers
	# only what the player doesn't own yet).
	var p = app.profile
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 12)
	root.add_child(grid)
	for pid in Eco.PACKS:
		var pk: Dictionary = Eco.PACKS[pid]
		var rar := str(pk.rarity)
		var c := Control.new()
		c.custom_minimum_size = Vector2(0, 232)
		UI.grow(c)
		grid.add_child(c)
		var clip := Control.new()
		clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		clip.offset_left = 4
		clip.offset_top = 4
		clip.offset_right = -4
		clip.offset_bottom = -4
		clip.clip_contents = true
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(clip)
		UI2.plate(c, _rar_panel(rar), 18.0, _rar_rim(rar))
		var ry := UI2.rays(clip, 230.0, _rar_tint(rar), 26.0, 0.4)
		ry.position = Vector2(-30, -80)
		var icons := []
		for id in pk.items:
			var tp := item_texture_path(str(id))
			if tp != "" and UI2.tex(tp) != null:
				icons.append([str(id), tp])
		var fan := [[Vector2(10, 10), -12.0], [Vector2(60, 22), 10.0], [Vector2(36, 2), 0.0]]
		for k in mini(icons.size(), 3):
			var ti := UI2.img(c, str(icons[k][1]), 92.0)
			ti.position = fan[k][0]
			ti.pivot_offset = Vector2(46, 46)
			ti.rotation = deg_to_rad(fan[k][1])
			if p.owns(str(icons[k][0])):
				ti.modulate = Color(1, 1, 1, 0.45)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 10
		v.offset_right = -10
		v.offset_top = 116
		v.offset_bottom = -50
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(v)
		UI2.text(v, str(pk.name).to_upper(), 15, Color.WHITE, UI2.INK, 5)
		var names := []
		for id in pk.items:
			names.append(str(Eco.item(id).name))
		var tl := UI2.body(v, " · ".join(names), 10, Color("#efe6ff"))
		tl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		var gems := Eco.pack_price(pid, p.d.owned)
		if gems <= 0:
			var ob := UI2.chip(c, "OWNED", Color("#27a248"), Color.WHITE)
			ob.position = Vector2(12, 192)
			continue
		var b := UI2.button(c, str(UI.compact(gems)), "purple", func(): buy_pack(app, pid), "buy_" + pid, 17, 36.0, 11.0, "res://assets/ui/currency/gem.png")
		b.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		b.offset_left = 10
		b.offset_right = -10
		b.offset_top = -48
		b.offset_bottom = -10
		b.disabled = not p.can_afford({"gems": gems})

static func _rar_panel(rar: String) -> String:
	return {"common": "night", "rare": "royal", "epic": "purple", "legendary": "ember"}.get(rar, "night")

static func _rar_rim(rar: String) -> String:
	return {"common": "silver", "rare": "blue", "epic": "purple", "legendary": "orange"}.get(rar, "gold")

static func _rar_tint(rar: String) -> Color:
	return {"common": Color(0.85, 0.88, 1.0), "rare": Color(0.55, 0.78, 1.0), "epic": Color(0.85, 0.6, 1.0), "legendary": Color(1.0, 0.78, 0.35)}.get(rar, Color(1, 0.9, 0.6))

static func buy_pack(app, pid: String) -> void:
	var pk: Dictionary = Eco.PACKS[pid]
	var gems := Eco.pack_price(pid, app.profile.d.owned)
	app.confirm("BUY %s?" % str(pk.name).to_upper(), "%d items for %d gems." % [pk.items.size(), gems], "BUY", "premium", func():
		var r: Dictionary = app.profile.buy_pack(pid)
		if r.ok:
			app.sfx("purchase")
			app.toast("Unlocked the %s — equip it in the Locker" % str(pk.name), UI.GOLD)
		else:
			app.sfx("error")
			app.toast(str(r.error), UI.RED)
		app.rebuild())

static func price_button(parent: Node, app, id: String, size := 15, h := 34.0) -> Button:
	var price := Eco.item_price(id)
	var gems: bool = price.has("gems")
	var amount: int = int(price.get("gems", price.get("gold", 0)))
	var b := UI2.button(parent, UI.compact(amount), "purple" if gems else "gold", func(): buy(app, id), "buy_" + id, size, h, 11.0,
		"res://assets/ui/currency/%s.png" % ("gem" if gems else "coin"))
	b.disabled = not app.profile.can_afford(price)
	return b

static func buy(app, id: String) -> void:
	var it := Eco.item(id)
	var price := Eco.item_price(id)
	var do_buy := func():
		var r: Dictionary = app.profile.buy(id)
		if r.ok:
			app.sfx("purchase")
			app.toast("Unlocked %s — equip it in the Locker" % str(it.name), UI.GOLD)
		else:
			app.sfx("error")
			app.toast(str(r.error), UI.RED)
		app.rebuild()
	if price.has("gems"):
		app.confirm("BUY %s?" % str(it.name).to_upper(), "%s for %d gems." % [item_kind_text(it), int(price.gems)], "BUY", "premium", do_buy)
	else:
		do_buy.call()

# ---------------- HOME ----------------
# 0.31.79 (Kevin: the concepts, "build it"): the painted battlements with every class on the dais (the app's hero layer),
# PASS / ORDERS / FIRST WIN medallions, the roster ribbon, one big PLAY (always the server), the chests in 3D, then
# the orders and the pass under it. The top is laid out by hand in content pixels (the hero layer lines up with it).
const HOME_TOP := 776.0

static func home(app, root: VBoxContainer) -> void:
	var p = app.profile
	var d: Dictionary = p.d
	app.hero_show()
	var w: float = maxf(300.0, app.size.x - 24.0)
	var top := Control.new()
	top.custom_minimum_size = Vector2(0, HOME_TOP)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var refs := {}
	if d.has("refund_note"):                              # 0.31.39: skins removed -- tell them once what came back
		var rn: Dictionary = d.refund_note
		app.toast("Skins have been retired -- refunded %s" % ", ".join([("%d gold" % int(rn.gold)) if int(rn.gold) > 0 else "", ("%d gems" % int(rn.gems)) if int(rn.gems) > 0 else ""].filter(func(x): return x != "")), UI.GOLD)
		d.erase("refund_note")
		p.save()
	# --- side medallions
	var claimable := 0
	for t in range(1, p.pass_tier() + 1):
		for prem in [false, true]:
			if p.can_claim(t, prem):
				claimable += 1
	var orders_ready := 0
	for span in ["daily", "weekly"]:
		for ch in (d.challenges.daily if span == "daily" else d.challenges.weekly):
			if not bool(ch.claimed) and int(ch.progress) >= int(Eco.CHALLENGES[ch.id].goal):
				orders_ready += 1
	var sp := _medallion(top, Vector2(-2, 58), "banner", "PASS", func(): app.show_tab("pass"), "side_pass", claimable)
	if claimable > 0:
		UI2.wiggle(sp.get_meta("icon"))
	_medallion(top, Vector2(-2, 150), "scroll", "ORDERS", func():
		app.sfx("tap")
		if refs.has("orders"):
			app.content_scroll.ensure_control_visible(refs.orders), "side_orders", orders_ready)
	var fw_open := str(d.first_win_day) != Eco.day_key(p.now())
	var fwb := _medallion(top, Vector2(w - 62, 58), "trophy", "FIRST WIN", func():
		app.sfx("tap")
		if fw_open:
			app.toast("First win of the day: +%d gold, +%d pass XP and a Silver Chest" % [Eco.FIRST_WIN.gold, Eco.FIRST_WIN.pass], UI.GOLD)
		else:
			app.toast("First win done today -- back tomorrow", UI.MUTED), "side_first_win", 0, "silver")
	if fw_open:
		UI2.bob(fwb.get_meta("icon"), 4.0, 1.4)
		var chip := PanelContainer.new()
		var cs := StyleBoxFlat.new()
		cs.bg_color = Color("#ffc94d")
		cs.border_color = Color("#3a1c02")
		cs.set_border_width_all(2)
		cs.set_corner_radius_all(9)
		cs.content_margin_left = 6
		cs.content_margin_right = 6
		chip.add_theme_stylebox_override("panel", cs)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.position = Vector2(w - 58, 58 + 90)
		chip.custom_minimum_size = Vector2(56, 18)
		top.add_child(chip)
		var cl := UI.label(chip, "+%d" % Eco.FIRST_WIN.gold, 11, Color("#3a1c02"), UI.HEAVY_FONT)
		cl.autowrap_mode = TextServer.AUTOWRAP_OFF
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		fwb.modulate = Color(0.75, 0.75, 0.8, 0.85)
	# --- the roster ribbon
	var rib := UI2.ribbon(top, "16 v 16 SIEGE", "7 classes  ·  grab a hat in battle to become one", 330.0, 52.0)
	rib.position = Vector2((w - 330.0) * 0.5, 420)
	# --- PLAY: always the Siege server (0.31.79); the bots fill any empty slots
	UI2.glow(top, Rect2(-30, 470, w + 60, 130), Color(1.0, 0.55, 0.15, 0.55))
	var play := UI2.button(top, "", "orange", func(): app.start_match(true), "play", 20, 84.0, 22.0)
	play.position = Vector2(0, 486)
	play.size = Vector2(w, 84)
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 12)
	pr.alignment = BoxContainer.ALIGNMENT_CENTER
	pr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pr.offset_bottom = -8
	pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play.add_child(pr)
	UI2.icon(pr, "swords", 58.0).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pl := UI2.text(pr, "PLAY", 54, Color.WHITE, Color("#5a2205"), 11)
	pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UI2.sweep(play, 2.6, 80.0, 0.5)
	UI2.pulse(play, 0.018, 1.1)
	var hint := HBoxContainer.new()
	hint.add_theme_constant_override("separation", 6)
	hint.alignment = BoxContainer.ALIGNMENT_CENTER
	hint.position = Vector2(0, 578)
	hint.size = Vector2(w, 18)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(hint)
	var dot := Panel.new()
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color("#5fdc86")
	ds.set_corner_radius_all(4)
	ds.shadow_color = Color(0.37, 0.86, 0.53, 0.7)
	ds.shadow_size = 4
	dot.add_theme_stylebox_override("panel", ds)
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_child(dot)
	UI2.body(hint, "Live 16 vs 16 on the Siege server  ·  bots fill any empty slots", 11, Color("#c2cdea"), false)
	# --- chests
	chests_row(app, top, w, 640.0)
	var odds := UI2.button(top, "WHAT'S INSIDE THE CHESTS?", "ghost", func(): chest_odds(app), "chest_odds", 12, 28.0, 10.0)
	odds.position = Vector2((w - 230.0) * 0.5, 740)
	odds.size = Vector2(230, 28)
	if bool(app.get("safe_boot")):
		# 0.31.70: the last start never reached the menu, so this one skipped the live hero and the background
		# loading. Hand the tester the start-up log (phases, errors, logcat) to send.
		var sb := UI2.frame(root, "ember", 12, 16.0, "orange")
		UI2.center(UI2.text(sb, "SAFE START", 18, Color.WHITE))
		UI2.center(UI2.body(sb, "The game got stuck starting last time, so this start skipped the 3D heroes. Please copy the diagnostics and send them to the developer.", 12, Color.WHITE))
		UI2.button(sb, "COPY DIAGNOSTICS", "blue", func():
			DisplayServer.clipboard_set(Diag.read_logs())
			app.toast("Diagnostics copied -- paste them to the developer", UI.CYAN), "copy_diag_boot", 15, 44.0)
	if not bool(d.get("tutorial_done", false)):
		# First visit: the Herald offers the walkthrough (0.19.0).
		var tc := UI2.frame(root, "parch", 12, 16.0, "brown")
		var tr := UI.row(tc, 10)
		UI2.icon(tr, "crown", 44.0)
		var tl := UI2.body(tr, "New here? The Royal Herald will show you the ropes. (+%d gold)" % app.TUTORIAL_GOLD, 14, Color("#3b2412"))
		tl.remove_theme_color_override("font_shadow_color")
		UI.grow(tl)
		UI2.button(tc, "PLAY TUTORIAL", "gold", func(): app.start_tutorial(), "tutorial_start", 18, 46.0)
	var how := UI2.button(root, "HOW TO PLAY", "ghost", func(): app.start_tutorial(), "tutorial", 14, 36.0, 12.0)
	how.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	how.custom_minimum_size = Vector2(170, 36)
	refs["orders"] = challenges_card(app, root, "daily")
	challenges_card(app, root, "weekly")
	pass_card(app, root)

static func _medallion(parent: Control, at: Vector2, icon: String, label: String, on_press: Callable, key: String, badge := 0, rim := "gold") -> Button:
	# A round gold-rimmed medallion with a 3D icon in it and a label under it (Home's side buttons).
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	for st_name in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st_name, StyleBoxEmpty.new())
	b.position = at
	b.size = Vector2(66, 88)
	b.set_meta("action_key", key)
	b.pressed.connect(on_press)
	parent.add_child(b)
	var disc := Control.new()
	disc.position = Vector2(2, 0)
	disc.size = Vector2(62, 62)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(disc)
	UI2.plate(disc, "royal", 31.0, rim, {"rim": 3.0, "shadow_y": 5.0})
	if badge > 0 and rim == "gold":
		UI2.glow(b, Rect2(-14, -14, 94, 94), Color(1.0, 0.85, 0.4, 0.5))
	var ic := UI2.icon(b, icon, 52.0)
	ic.position = Vector2(7, 3)
	ic.pivot_offset = Vector2(26, 26)
	b.set_meta("icon", ic)
	var l := UI2.text(b, label, 12, Color.WHITE, UI2.INK, 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(-12, 62)
	l.size = Vector2(90, 18)
	if badge > 0:
		UI2.badge(disc, str(badge), Vector2(6, -6))
	return b

# ---------- chests (0.31.37; 0.31.79 in 3D) ----------
static func chests_row(app, parent: Control, w: float, y: float) -> void:
	var p = app.profile
	var busy: Dictionary = p.unlocking()
	var gap := 8.0
	var sw := (w - gap * 3.0) / 4.0
	var sh := 88.0
	var slots := []
	var cells := []
	for i in Eco.CHEST_SLOTS:                           # the slot plates (under the chests)
		var x := i * (sw + gap)
		var plate := Control.new()
		plate.position = Vector2(x, y)
		plate.size = Vector2(sw, sh)
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(plate)
		if i >= p.chests().size():
			UI2.plate(plate, "glass", 14.0)
			continue
		var ch: Dictionary = p.chests()[i]
		var k := str(ch.kind)
		var ready: bool = p.chest_ready(ch)
		var rim: String = {"wooden": "brown", "silver": "silver", "gold": "gold", "royal": "purple"}.get(k, "gold")
		if ready:
			UI2.glow(plate, Rect2(-14, -40, sw + 28, sh + 40), Color(0.55, 1.0, 0.6, 0.55))
		UI2.plate(plate, "green" if ready else "night", 14.0, rim)
		slots.append({"kind": k, "mode": "tease" if ready else "idle", "x": x + sw * 0.5})
	var row := ChestRow.new()                           # the chests themselves, in 3D
	row.slots = slots
	row.position = Vector2(0, y - 46)
	row.size = Vector2(w, 110)
	row.chest_px = minf(80.0, sw - 6.0)
	row.base_y = 0.66
	parent.add_child(row)
	for i in Eco.CHEST_SLOTS:                           # and what's on each slot (over the chests)
		var x := i * (sw + gap)
		var cell := Control.new()
		cell.position = Vector2(x, y)
		cell.size = Vector2(sw, sh)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(cell)
		if i >= p.chests().size():
			var e := UI2.body(cell, "Win to earn\na chest", 10, UI2.MUTED)
			e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			e.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			e.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			continue
		var ch: Dictionary = p.chests()[i]
		var k := str(ch.kind)
		var ready: bool = p.chest_ready(ch)
		var idx := i
		if ready:
			var ob := UI2.button(cell, "OPEN", "green", func(): open_chest(app, idx), "chest_open_%d" % i, 15, 28.0, 9.0)
			ob.position = Vector2(8, sh - 36)
			ob.size = Vector2(sw - 16, 28)
			UI2.sweep(ob, 2.2, 30.0, 0.6)
		elif int(ch.start) >= 0:
			_slot_tag(cell, UI.duration(p.chest_left(ch)), UI2.GOLD)
			var frac := 1.0 - float(p.chest_left(ch)) / float(Eco.CHESTS[k].unlock)
			var pb := UI2.bar(cell, frac, 1.0, Color("#fff1a6"), Color("#f0a024"), 7.0)
			pb.position = Vector2(10, sh - 46)
			pb.size = Vector2(sw - 20, 7)
			var sb := UI2.button(cell, "%d" % Eco.skip_cost(p.chest_left(ch)), "purple", func(): skip_chest(app, idx), "chest_skip_%d" % i, 14, 28.0, 9.0, "res://assets/ui/currency/gem.png")
			sb.position = Vector2(8, sh - 36)
			sb.size = Vector2(sw - 16, 28)
		elif busy.is_empty():
			_slot_tag(cell, UI.duration(p.chest_left(ch)), Color.WHITE)
			var ub := UI2.button(cell, "UNLOCK", "blue", func():
				p.start_unlock(idx)
				app.sfx("tap")
				app.rebuild(), "chest_unlock_%d" % i, 13, 28.0, 9.0)
			ub.position = Vector2(8, sh - 36)
			ub.size = Vector2(sw - 16, 28)
		else:
			_slot_tag(cell, "QUEUED", UI2.MUTED)
			var tr := HBoxContainer.new()
			tr.alignment = BoxContainer.ALIGNMENT_CENTER
			tr.add_theme_constant_override("separation", 3)
			tr.position = Vector2(0, sh - 34)
			tr.size = Vector2(sw, 24)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(tr)
			UI2.icon(tr, "hourglass", 20.0)
			UI2.text(tr, UI.duration(p.chest_left(ch)), 15, Color.WHITE, Color("#0e1433"), 4)
			var skip := UI2.button(cell, "", "ghost", func(): skip_chest(app, idx), "chest_skip_%d" % i, 10, 20.0, 8.0)
			skip.position = Vector2(4, 4)
			skip.size = Vector2(sw - 8, sh - 40)
			skip.self_modulate = Color(1, 1, 1, 0)

static func _slot_tag(cell: Control, s: String, col: Color) -> void:
	var c := UI2.chip(cell, s, Color(0.01, 0.02, 0.08, 0.88), col, Color(col, 0.7))
	c.anchor_left = 1.0
	c.anchor_right = 1.0
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	c.offset_right = -4
	c.offset_left = -60
	c.offset_top = 4
	c.offset_bottom = 20

static func skip_chest(app, idx: int) -> void:
	var r: Dictionary = app.profile.skip_chest(idx)
	if bool(r.get("ok", false)):
		app.sfx("tap")
		open_chest(app, idx)
	else:
		app.sfx("error")
		app.toast("Not enough gems (%d needed)" % int(r.get("cost", 0)), UI.RED)

static func open_chest(app, idx: int) -> void:
	# 0.31.79: the 3D opening (chest_open.gd); the roll happens when the chest is tapped open.
	var chs: Array = app.profile.chests()
	if idx < 0 or idx >= chs.size() or not app.profile.chest_ready(chs[idx]):
		return
	app.sfx("tap")
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
		var def: Dictionary = Eco.CHALLENGES[ch.id]
		var row := UI.row(c, 10)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 3)
		UI.grow(v)
		row.add_child(v)
		UI.label(v, str(def.text), 13, ink, UI.HEAVY_FONT)
		var reward := "+%d pass XP" % int(def.pass)
		if def.has("gold"):
			reward += " · +%d gold" % int(def.gold)
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
					app.sfx("coin")
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
	# offer, the season's best item turning in 3D, then the track -- free on the left, premium on the right, a gold spine.
	var p = app.profile
	var d: Dictionary = p.d
	var sid: int = int(d.pass.season)
	var tier: int = p.pass_tier()
	var items: Array = Eco.pass_items(sid)

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

	# --- premium
	var legendary := 0
	for k in range(Eco.PASS_FREE_ITEMS, items.size()):
		if str(Eco.CATALOG[items[k]].rarity) == "legendary":
			legendary += 1
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
		UI2.body(pt, "%d exclusive cosmetics (%d legendary) · gold chests · a Royal chest · more gems on every tier" % [Eco.PASS_PREMIUM_ITEMS, legendary], 12, Color("#efe2ff"))
		var b := UI2.button(pc, "UNLOCK  %d" % Eco.PREMIUM_COST, "purple", func(): _buy_premium(app), "buy_premium", 20, 52.0, 16.0, "res://assets/ui/currency/gem.png")
		b.disabled = int(d.gems) < Eco.PREMIUM_COST
		UI2.sweep(b)
		UI2.center(UI2.body(pc, "You have %d gems" % int(d.gems), 11, Color("#d8c6ff")))

	# --- the season's best: premium tier 30, turning
	var best: String = str(items[items.size() - 1])
	var bit: Dictionary = Eco.CATALOG[best]
	var fr: String = {"legendary": "ember", "epic": "purple", "rare": "royal"}.get(str(bit.rarity), "night")
	var rim: String = {"legendary": "orange", "epic": "purple", "rare": "blue"}.get(str(bit.rarity), "gold")
	var fc := Control.new()
	fc.custom_minimum_size = Vector2(0, 236)
	root.add_child(fc)
	var stage := Control.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.offset_left = 5
	stage.offset_top = 5
	stage.offset_right = -5
	stage.offset_bottom = -5
	stage.clip_contents = true
	fc.add_child(stage)
	UI2.plate(fc, fr, 20.0, rim, {"rim": 4.0})
	var sr := UI2.rays(stage, 420.0, Color(1.0, 0.75, 0.35) if fr == "ember" else Color(0.85, 0.6, 1.0), 30.0, 0.5)
	stage.resized.connect(func(): sr.position = Vector2(stage.size.x * 0.32 - 210.0, stage.size.y * 0.5 - 210.0))
	if str(bit.kind) == "weapon":
		var sh := Showcase.new()
		sh.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		sh.anchor_right = 0.66
		stage.add_child(sh)
		sh.show_look(str(bit["class"]), {"r": str(bit.get("r", "")), "l": str(bit.get("l", ""))})
	var cap := VBoxContainer.new()
	cap.add_theme_constant_override("separation", 4)
	cap.anchor_left = 0.56
	cap.anchor_right = 1.0
	cap.anchor_bottom = 1.0
	cap.offset_top = 22
	cap.offset_right = -12
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(cap)
	UI2.body(cap, "THIS SEASON'S PRIZE", 10, Color("#ffe0a8"))
	var bn := UI2.text(cap, str(bit.name).to_upper(), 24, Color("#ffbf4d") if fr == "ember" else UI2.PURPLE)
	bn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UI2.body(cap, "TIER 30  ·  %s" % str(bit.rarity).to_upper(), 11, Color.WHITE)
	if str(bit.kind) == "weapon":
		UI2.body(cap, "%s weapon on the premium track" % str(Eco.CLASS_NAMES.get(str(bit["class"]), "")), 11, Color("#f3d6b8"))
	UI2.body(cap, "Tap to look closer", 10, Color(1, 1, 1, 0.6))
	var tap := Button.new()
	tap.flat = true
	for st_name in ["normal", "hover", "pressed", "focus"]:
		tap.add_theme_stylebox_override(st_name, StyleBoxEmpty.new())
	tap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tap.pressed.connect(func(): open_pass_item(app, sid, Eco.PASS_TIERS, true))
	stage.add_child(tap)

	# --- claim all
	var claimable := 0
	for t in range(1, tier + 1):
		for prem in [false, true]:
			if p.can_claim(t, prem):
				claimable += 1
	if claimable > 0:
		var ca := UI2.button(root, "CLAIM ALL  (%d)" % claimable, "green", func():
			var got: Array = p.claim_all()
			app.sfx("coin")
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
	var r: Dictionary = Eco.pass_reward(sid, t, prem)
	var rt: Array = reward_text(r)
	var it: Dictionary = Eco.item(str(r.get("item", "")))
	var claimed: bool = (p.d.pass.prem if prem else p.d.pass.free).has(t)
	var ready: bool = p.can_claim(t, prem)
	var locked_prem: bool = prem and not bool(p.d.pass.premium)
	var locked: bool = t > p.pass_tier()
	var kind := "purple" if prem else "royal"
	var rim := "purple" if prem else "gold"
	if ready:
		kind = "green"
		rim = "green"
	elif not it.is_empty():
		rim = {"legendary": "orange", "epic": "purple", "rare": "blue"}.get(str(it.rarity), rim)
	var cell := Control.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.custom_minimum_size = Vector2(0, 116 if ready else 104)
	parent.add_child(cell)
	if ready:
		var g := UI2.glow(cell, Rect2(-16, -16, 10, 10), Color(0.55, 1.0, 0.6, 0.5))
		cell.resized.connect(func(): g.size = cell.size + Vector2(32, 32))
	UI2.plate(cell, kind, 16.0, rim, {"dim": 0.45 if (claimed or locked_prem) else 0.0})
	if not it.is_empty() and str(it.rarity) in ["epic", "legendary"] and not claimed:
		var rays := UI2.rays(cell, 150.0, Color(1, 0.8, 0.4) if str(it.rarity) == "legendary" else Color(0.85, 0.6, 1.0), 20.0, 0.35)
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
	if not it.is_empty():
		var rl := UI2.body(v, str(it.rarity).to_upper(), 9, rt[2].lightened(0.3), false)
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
		app.sfx("coin")
		var got: Array = reward_text(res.reward)
		app.toast("+ " + str(got[1]), UI.GREEN)
	app.close_modal()
	app.rebuild()

static func _buy_premium(app) -> void:
	var p = app.profile
	app.confirm("UNLOCK PREMIUM?", "%d exclusive cosmetics, gold and Royal chests and more gems on every tier this season. Costs %d gems." % [Eco.PASS_PREMIUM_ITEMS, Eco.PREMIUM_COST], "UNLOCK", "premium", func():
		var r: Dictionary = p.buy_premium()
		if r.ok:
			app.sfx("purchase")
			app.toast("Premium pass unlocked!", UI.PURPLE)
		else:
			app.sfx("error")
			app.toast(str(r.error), UI.RED)
		app.rebuild())

static func open_pass_item(app, sid: int, t: int, prem: bool) -> void:
	# the detail view: the reward big -- a weapon in its class's hands, turning with your finger
	var p = app.profile
	var r: Dictionary = Eco.pass_reward(sid, t, prem)
	var rt: Array = reward_text(r)
	var it: Dictionary = Eco.item(str(r.get("item", "")))
	app.sfx("tap")
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
	var edge: Color = rt[2] if not it.is_empty() else (PASS_PURPLE if prem else PASS_GOLD)
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
	if str(it.get("kind", "")) == "weapon":
		Showcase.backdrop(stage)
		var sh := Showcase.new()
		sh.interactive = true
		sh.cam_z = 5.6
		sh.cam_y = 1.35
		sh.look_y = 0.95
		sh.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stage.add_child(sh)
		sh.show_look(str(it["class"]), {"r": str(it.get("r", "")), "l": str(it.get("l", ""))})
		zoom_controls(stage, sh, "pass")
	else:
		Showcase.backdrop(stage)
		var cc := CenterContainer.new()
		cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stage.add_child(cc)
		var cv := VBoxContainer.new()
		cc.add_child(cv)
		if str(it.get("kind", "")) == "title":
			var tt := UI.label(cv, "« %s »" % str(it.name), 30, PASS_GOLD, UI.TITLE_FONT, true)
			tt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			UI.label(cv, "a title shown next to your name", 12, Color.WHITE).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		else:
			var icc := CenterContainer.new()
			cv.add_child(icc)
			if str(rt[3]) != "":
				UI.tex_icon(icc, str(rt[3]), 120)
			else:
				UI.icon(icc, str(rt[0]), 96, rt[2])
	var nm := UI.label(v, str(rt[1]), 24, Color.WHITE, UI.TITLE_FONT, true)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not it.is_empty():
		var ir := UI.row(v, 8)
		ir.alignment = BoxContainer.ALIGNMENT_CENTER
		_chip(ir, str(it.rarity).to_upper(), rt[2], Color("#120c22"))
		if str(it.get("kind", "")) == "weapon":
			_chip(ir, str(Eco.CLASS_NAMES.get(str(it["class"]), "")).to_upper() + " WEAPON", Color(1, 1, 1, 0.12), Color.WHITE)
		if p.owns(str(r.item)):
			_chip(ir, "OWNED", UI.GREEN, Color("#0c2014"))
	elif r.has("chest"):
		var cd := UI.label(v, Eco.chest_odds(str(r.chest)), 11, UI.MUTED)
		cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
	# 0.31.79: the market stall banner, this week's featured item big (its class holding it, turning), the daily deals,
	# the Arsenals and the gem exchange.
	var p = app.profile
	var now: int = p.now()
	var ban := banner(root, UI2.V2 + "art_shop.webp", "MARKET", 196.0)
	var note := UI2.chip(ban, "EVERYTHING HERE IS COSMETIC", Color(0.03, 0.02, 0.1, 0.8), UI2.CREAM, Color(UI2.GOLD, 0.6))
	note.position = Vector2(12, 12)
	var days := int(floor(now / 86400.0))
	var monday := days - ((days + 3) % 7)
	UI2.divider(root, "FEATURED", 22, "new picks in " + UI.duration((monday + 7) * 86400 - now))
	var feat: Array = Eco.shop_featured(now)
	var sel := clampi(int(app.get_meta("shop_feat", 0)), 0, maxi(0, feat.size() - 1))
	if not feat.is_empty():
		featured_card(app, root, str(feat[sel]))
		var thumbs := HBoxContainer.new()
		thumbs.alignment = BoxContainer.ALIGNMENT_CENTER
		thumbs.add_theme_constant_override("separation", 14)
		root.add_child(thumbs)
		for i in feat.size():
			var fid := str(feat[i])
			var on := i == sel
			var tb := Button.new()
			tb.flat = true
			tb.focus_mode = Control.FOCUS_NONE
			for st_name in ["normal", "hover", "pressed", "focus"]:
				tb.add_theme_stylebox_override(st_name, StyleBoxEmpty.new())
			tb.custom_minimum_size = Vector2(68, 68)
			tb.set_meta("action_key", "feat_%d" % i)
			var ii := i
			tb.pressed.connect(func():
				app.sfx("tap")
				app.set_meta("shop_feat", ii)
				app.rebuild())
			thumbs.add_child(tb)
			if on:
				UI2.skin(tb, UI2.button_params("gold", 16.0, 3.0))
			else:
				UI2.plate(tb, _rar_panel(str(Eco.item(fid).rarity)), 16.0, _rar_rim(str(Eco.item(fid).rarity)), {"rim": 2.0, "dim": 0.25})
			var ti := UI2.img(tb, item_texture_path(fid), 56.0)
			ti.position = Vector2(6, 4)
	UI2.divider(root, "DAILY DEALS", 22, "new in %s  ·  paid with gold you earn" % UI.duration((days + 1) * 86400 - now))
	item_grid(app, root, Eco.shop_daily(now), false)
	UI2.divider(root, "ARSENALS", 22, "bundles for one class")
	pack_list(app, root)
	UI2.divider(root, "GEMS  →  GOLD", 22, "trade gems for gold any time")
	var ex := HBoxContainer.new()
	ex.add_theme_constant_override("separation", 10)
	root.add_child(ex)
	var n := 0
	for off in Eco.EXCHANGE:
		var best: bool = n == Eco.EXCHANGE.size() - 1
		var c := Control.new()
		c.custom_minimum_size = Vector2(0, 168)
		UI.grow(c)
		ex.add_child(c)
		if best:
			UI2.glow(c, Rect2(-16, -16, 10, 10), Color(1.0, 0.85, 0.4, 0.5))
			var gw := c.get_child(c.get_child_count() - 1) as Control
			c.resized.connect(func(): gw.size = c.size + Vector2(32, 32))
		UI2.plate(c, "royal" if best else "night", 18.0, "gold")
		var pile := UI2.img(c, "res://assets/ui/currency/coins_%s.png" % str(off.id).substr(5), 80.0)
		c.resized.connect(func(): pile.position = Vector2((c.size.x - 80.0) * 0.5, 8))
		var gl := UI2.text(c, "+" + UI.compact(int(off.gold)), 20, UI2.GOLD, UI2.INK, 5)
		gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		gl.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		gl.offset_top = 90
		gl.offset_bottom = 114
		var oid: String = off.id
		var b := UI2.button(c, str(int(off.gems)), "purple", func():
			var r: Dictionary = p.exchange(oid)
			if r.ok:
				app.sfx("coin")
				app.toast("+%s gold" % UI.compact(int(off.gold)), UI.GOLD)
			else:
				app.sfx("error")
				app.toast(str(r.error), UI.RED)
			app.rebuild(), "exchange_" + oid, 16, 36.0, 11.0, "res://assets/ui/currency/gem.png")
		b.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		b.offset_left = 8
		b.offset_right = -8
		b.offset_top = -46
		b.offset_bottom = -8
		b.disabled = int(p.d.gems) < int(off.gems)
		if best:
			var bv := UI2.chip(c, "BEST VALUE", Color("#e8443a"), Color.WHITE, Color("#3a0805"))
			bv.anchor_left = 0.5
			bv.anchor_right = 0.5
			bv.offset_left = -40
			bv.offset_right = 40
			bv.offset_top = -10
			bv.offset_bottom = 8
		n += 1
	var fn := UI2.body(root, "Chests are earned by playing  ·  never sold", 11, Color("#cdb79a"))
	fn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

static func featured_card(app, root: Node, id: String) -> void:
	var p = app.profile
	var it := Eco.item(id)
	var rar := str(it.get("rarity", "epic"))
	var fc := Control.new()
	fc.custom_minimum_size = Vector2(0, 262)
	root.add_child(fc)
	var stage := Control.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.offset_left = 5
	stage.offset_top = 5
	stage.offset_right = -5
	stage.offset_bottom = -5
	stage.clip_contents = true
	fc.add_child(stage)
	UI2.plate(fc, _rar_panel(rar), 22.0, _rar_rim(rar), {"rim": 4.0})
	var sr := UI2.rays(stage, 440.0, _rar_tint(rar), 30.0, 0.5)
	stage.resized.connect(func(): sr.position = Vector2(stage.size.x * 0.3 - 220.0, stage.size.y * 0.5 - 220.0))
	if str(it.get("kind", "")) == "weapon":
		var sh := Showcase.new()
		sh.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		sh.anchor_right = 0.6
		stage.add_child(sh)
		sh.show_look(str(it["class"]), {"r": str(it.get("r", "")), "l": str(it.get("l", ""))})
	var cap := VBoxContainer.new()
	cap.add_theme_constant_override("separation", 6)
	cap.anchor_left = 0.56
	cap.anchor_right = 1.0
	cap.anchor_bottom = 1.0
	cap.offset_top = 18
	cap.offset_right = -12
	cap.offset_bottom = -14
	stage.add_child(cap)
	UI2.chip(cap, "%s  ·  %s" % [rar.to_upper(), str(Eco.CLASS_NAMES.get(str(it.get("class", "")), "")).to_upper()], Color(0.05, 0.02, 0.12, 0.8), _rar_tint(rar).lightened(0.3), Color(_rar_tint(rar), 0.8))
	var nl := UI2.text(cap, str(it.name).to_upper(), 22, Color.WHITE, UI2.INK, 6)
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UI2.body(cap, "Changes your look only. Every weapon plays the same.", 11, Color("#efe6ff"))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.add_child(sp)
	if p.owns(id):
		var eq: bool = is_equipped(p, id)
		var eb := UI2.button(cap, "EQUIPPED" if eq else "EQUIP", "green" if not eq else "grey", func(): equip(app, id), "equip_" + id, 17, 44.0)
		eb.disabled = eq
	else:
		var pb := price_button(cap, app, id, 20, 50.0)
		UI2.sweep(pb)

static func item_grid(app, root: Node, ids: Array, big: bool) -> void:
	var grid := GridContainer.new()
	grid.columns = 2 if big else 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 12)
	root.add_child(grid)
	for id in ids:
		var it := Eco.item(id)
		var p = app.profile
		var rar := str(it.get("rarity", "rare"))
		var c := Control.new()
		c.custom_minimum_size = Vector2(0, 206)
		UI.grow(c)
		grid.add_child(c)
		UI2.plate(c, _rar_panel(rar), 18.0, _rar_rim(rar))
		var g := UI2.glow(c, Rect2(0, 0, 10, 10), Color(_rar_tint(rar), 0.6))
		c.resized.connect(func():
			g.position = Vector2(c.size.x * 0.5 - 60, -2)
			g.size = Vector2(120, 110))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 6
		v.offset_right = -6
		v.offset_top = 8
		v.offset_bottom = -46
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(v)
		var ti := UI2.img(v, item_texture_path(str(id)), 84.0)
		ti.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var nl := UI2.text(v, str(it.name).to_upper(), 12, Color.WHITE, UI2.INK, 4)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var kl := UI2.body(v, "%s · %s" % [rar.to_upper(), str(Eco.CLASS_NAMES.get(str(it.get("class", "")), "")).to_upper()], 9, _rar_tint(rar).lightened(0.35), false)
		kl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		kl.clip_text = true
		var b: Button
		if p.owns(id):
			var equipped: bool = is_equipped(p, id)
			b = UI2.button(c, "EQUIPPED" if equipped else "EQUIP", "grey" if equipped else "blue", func(): equip(app, id), "equip_" + id, 13, 34.0, 11.0)
			b.disabled = equipped
		else:
			b = price_button(c, app, id, 14, 34.0)
		b.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		b.offset_left = 6
		b.offset_right = -6
		b.offset_top = -44
		b.offset_bottom = -8

static func is_equipped(p, id: String) -> bool:
	var it := Eco.item(id)
	if it.is_empty():
		return false
	if it.kind == "title":
		return str(p.d.title) == id
	return str(p.d.equip[str(it["class"])][str(it.kind)]) == id

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
		var l := UI2.text(b, label, 9, UI2.GOLD if on else Color.WHITE, UI2.INK, 3, false)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.position = Vector2(-10, px + 1)
		l.size = Vector2(px + 20, 12)
	return b

static func locker(app, root: VBoxContainer) -> void:
	# 0.31.79: the vault -- the class picker as round portraits (base classes, then the hat upgrades), the hero on the
	# vault's pedestal (turn and zoom it), the nameplate and the weapons as cards.
	var p = app.profile
	var title := UI2.text(root, "LOCKER", 30, UI2.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var rail := UI2.frame(root, "glass", 8, 18.0)
	var r1 := HBoxContainer.new()
	r1.alignment = BoxContainer.ALIGNMENT_CENTER
	r1.add_theme_constant_override("separation", 4)
	rail.add_child(r1)
	for cls in Eco.CLASSES:
		var c: String = cls
		_class_coin(r1, cls, app.locker_class == cls, "locker_" + cls, func():
			app.locker_class = c
			app.sfx("tap")
			app.rebuild(), str(Eco.CLASS_NAMES[cls]).to_upper(), 44.0)
	var r2 := HBoxContainer.new()
	r2.alignment = BoxContainer.ALIGNMENT_CENTER
	r2.add_theme_constant_override("separation", 4)
	rail.add_child(r2)
	var short := {"crusader":"CRUSADER", "berserker":"BERSERK", "necromancer":"NECRO", "assassin":"ASSASSIN", "sniper":"RANGER", "archmage":"ARCHMAGE"}
	for ucls in Eco.UP_CLASSES:
		var u: String = ucls
		_class_coin(r2, ucls, app.locker_class == ucls, "locker_" + ucls, func():
			app.locker_class = u
			app.sfx("tap")
			app.rebuild(), str(short[ucls]), 40.0)
	var tsel: bool = app.locker_class == "titles"
	var tb := UI2.button(r2, "TITLES", "gold" if tsel else "blue", func():
		app.locker_class = "titles"
		app.sfx("tap")
		app.rebuild(), "locker_titles", 12, 40.0, 12.0)
	tb.custom_minimum_size.x = 62
	if app.locker_class == "titles":
		UI2.divider(root, "TITLES", 20, "shown next to your name")
		var none := UI2.frame(root, "night", 10, 14.0, "gold")
		var nr := UI.row(none, 8)
		UI.grow(UI2.text(nr, "NO TITLE", 15, Color.WHITE))
		var ne := UI2.button(nr, "EQUIPPED" if str(p.d.title) == "" else "EQUIP", "grey" if str(p.d.title) == "" else "blue", func():
			p.unequip("", "title")
			app.rebuild(), "equip_default_title", 13, 34.0, 11.0)
		ne.disabled = str(p.d.title) == ""
		ne.custom_minimum_size.x = 104
		for id in Eco.CATALOG:
			if Eco.CATALOG[id].kind == "title":
				locker_row(app, root, id)
		return
	var cls: String = app.locker_class
	# the vault
	var hero := Control.new()
	hero.custom_minimum_size = Vector2(0, 340)
	root.add_child(hero)
	var stage := Control.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.offset_left = 5
	stage.offset_top = 5
	stage.offset_right = -5
	stage.offset_bottom = -5
	stage.clip_contents = true
	hero.add_child(stage)
	UI2.plate(hero, "night", 22.0, "gold", {"rim": 4.0})
	var vault := TextureRect.new()
	vault.texture = UI2.tex(UI2.V2 + "bg_vault.webp")
	vault.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vault.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	vault.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vault.offset_top = -170
	vault.offset_bottom = 60
	vault.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(vault)
	var beam := UI2.glow(stage, Rect2(0, 0, 10, 10), Color(1.0, 0.9, 0.6, 0.35))
	stage.resized.connect(func():
		beam.size = Vector2(220, 300)
		beam.position = Vector2(stage.size.x * 0.5 - 110, 20))
	var show := Showcase.new()
	show.interactive = true                                  # 0.31.64 (Kevin): turn and zoom the hero in the locker too
	show.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(show)
	show.show_look(cls, p.look_for(cls))
	zoom_controls(stage, show, "locker")
	# nameplate
	var np := UI2.frame(root, "royal", 8, 16.0, "gold")
	var nm := UI2.text(np, str(Eco.CLASS_NAMES[cls]).to_upper(), 24, Color.WHITE, Color("#0e1433"))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := ""
	if Eco.UP_BASE.has(cls):
		sub = "From the %s stand once your team's workshop buys %s hats" % [str(Eco.CLASS_NAMES[Eco.UP_BASE[cls]]), str(Eco.CLASS_NAMES[cls])]
	else:
		var up := ""
		for u in Eco.UP_BASE:
			if Eco.UP_BASE[u] == cls:
				up = str(Eco.CLASS_NAMES[u])
		sub = ("Grab its hat at the %s stand  ·  upgrade: %s" % [str(Eco.CLASS_NAMES[cls]), up]) if up != "" else "Gathers wood and stone, repairs gates, pays for upgrades"
	UI2.center(UI2.body(np, sub, 11, Color("#ffe39a")))
	# weapons
	var owned := 1
	var total := 1
	for id in Eco.CATALOG:
		var it: Dictionary = Eco.CATALOG[id]
		if it.kind == "weapon" and str(it["class"]) == cls:
			total += 1
			if p.owns(id):
				owned += 1
	UI2.divider(root, "WEAPONS", 22, "%d of %d owned  ·  looks only, every weapon plays the same" % [owned, total])
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 12)
	root.add_child(grid)
	var is_def: bool = str(p.d.equip[cls]["weapon"]) == ""
	_gear_card(app, grid, "", cls, "res://assets/ui/icons/default_%s.png" % cls, "DEFAULT GEAR", "common", true, is_def)
	for id in Eco.CATALOG:
		var it: Dictionary = Eco.CATALOG[id]
		if it.kind == "weapon" and str(it["class"]) == cls:
			_gear_card(app, grid, str(id), cls, item_texture_path(str(id)), str(it.name).to_upper(), str(it.rarity), p.owns(id), is_equipped(p, id))

static func _gear_card(app, grid: Node, id: String, cls: String, icon: String, name: String, rar: String, owned: bool, equipped: bool) -> void:
	var p = app.profile
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 214)
	UI.grow(c)
	grid.add_child(c)
	if equipped:
		var g := UI2.glow(c, Rect2(-14, -14, 10, 10), Color(1.0, 0.85, 0.4, 0.5))
		c.resized.connect(func(): g.size = c.size + Vector2(28, 28))
	UI2.plate(c, _rar_panel(rar), 18.0, "gold" if equipped else _rar_rim(rar), {"dim": 0.0 if owned else 0.3})
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 8
	v.offset_right = -8
	v.offset_top = 8
	v.offset_bottom = -48
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(v)
	var ti := UI2.img(v, icon, 96.0)
	ti.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if not owned:
		ti.modulate = Color(0.65, 0.65, 0.72)
	elif equipped:
		UI2.bob(ti, 3.0, 1.2)
	var nl := UI2.text(v, name, 13, Color.WHITE, UI2.INK, 4)
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var rl := UI2.body(v, rar.to_upper(), 9, _rar_tint(rar).lightened(0.35), false)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var b: Button = null
	if owned:
		if id == "":
			b = UI2.button(c, "EQUIPPED" if equipped else "EQUIP", "gold" if equipped else "blue", func():
				p.unequip(cls, "weapon")
				app.sfx("equip")
				app.rebuild(), "equip_default_%s_weapon" % cls, 14, 34.0, 11.0)
		else:
			b = UI2.button(c, "EQUIPPED" if equipped else "EQUIP", "gold" if equipped else "blue", func(): equip(app, id), "equip_" + id, 14, 34.0, 11.0)
		b.disabled = equipped
	else:
		var it := Eco.item(id)
		var where := "Siege Pass reward"
		if str(it.get("source", "")) == "shop":
			var now: int = p.now()
			where = "In the shop today" if (Eco.shop_daily(now).has(id) or Eco.shop_featured(now).has(id)) else "Rotates through the shop"
		var wl := UI2.body(c, where, 10, UI2.SOFT, false)
		wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		wl.offset_top = -40
		wl.offset_bottom = -14
		var lk := Control.new()
		lk.size = Vector2(28, 28)
		lk.position = Vector2(6, 6)
		lk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(lk)
		UI2.plate(lk, "night", 14.0, "gold", {"rim": 0.0, "outline": 2.0, "outline_color": Color(1, 0.84, 0.35, 0.7)})
		var li := UI.icon(lk, "lock", 16, UI2.GOLD)
		li.position = Vector2(6, 5)
	if b != null:
		b.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		b.offset_left = 8
		b.offset_right = -8
		b.offset_top = -44
		b.offset_bottom = -8

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
	# (titles)
	var p = app.profile
	var it := Eco.item(id)
	var c := UI2.frame(root, _rar_panel(str(it.rarity)), 10, 14.0, _rar_rim(str(it.rarity)))
	var r := UI.row(c, 10)
	UI2.icon(r, "scroll", 40.0)
	var v := VBoxContainer.new()
	UI.grow(v)
	r.add_child(v)
	UI2.text(v, "« %s »" % str(it.name), 16, Color.WHITE)
	UI2.body(v, str(it.rarity).to_upper(), 10, _rar_tint(str(it.rarity)).lightened(0.3), false)
	if p.owns(id):
		var eq: bool = is_equipped(p, id)
		var b := UI2.button(r, "EQUIPPED" if eq else "EQUIP", "gold" if eq else "blue", func(): equip(app, id), "equip_" + id, 13, 34.0, 11.0)
		b.disabled = eq
		b.custom_minimum_size.x = 104
		return
	var where := "Siege Pass reward"
	if str(it.get("source", "")) == "shop":
		var now: int = p.now()
		where = "In the shop today" if (Eco.shop_daily(now).has(id) or Eco.shop_featured(now).has(id)) else "Rotates through the shop"
	UI2.body(v, where, 11, UI2.MUTED, false)
	UI.icon(r, "lock", 20, UI2.GOLD)
	(c.get_parent() as Control).modulate.a = 0.8

# ---------------- SETTINGS ----------------
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
		d.name = nm
		p.save()
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
	var tiles := [["swords", UI.compact(matches), "MATCHES"], ["trophy", UI.compact(wins), "WINS"], ["crown", UI.compact(int(st.rescues)), "RESCUES"],
		["skull", UI.compact(int(st.kills)), "KNOCKOUTS"], ["castle", UI.compact(int(st.gates) * 100), "GATE DMG"], ["stall", UI.compact(int(st.gathered)), "GATHERED"],
		["fish", UI.compact(int(st.fed)), "FISH FED"], ["banner", ("%d%%" % int(round(100.0 * wins / matches))) if matches > 0 else "--", "WIN RATE"]]
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
		sl.value = float(d.settings.get(key, 0.6 if key == "music" else 0.8))
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
			app._apply_audio())
	# Graphics
	var gx := UI2.frame(root, "night", 12, 18.0, "gold")
	UI2.divider(gx, "GRAPHICS", 20)
	UI2.toggle(gx, "High-quality graphics", "Shadows, glow, smooth edges", bool(d.settings.get("hq_graphics", true)), "hq_graphics", func(on: bool):
		d.settings.hq_graphics = on
		p.save())
	UI2.toggle(gx, "Reduce effects", "Smoother on older phones", bool(d.settings.get("reduce_motion", false)), "reduce_motion", func(on: bool):
		d.settings.reduce_motion = on
		p.save())
	# 0.31.72: the graphics engine. Vulkan by default; OpenGL when Godot finds no usable Vulkan, after a start on Vulkan
	# froze (BootGuard), or by choice here. Switching restarts the game.
	var guard = app.get_node_or_null("/root/BootGuard")
	if guard != null:
		var on_gl := RenderingServer.get_current_rendering_method() == "gl_compatibility"
		var by_file: bool = guard.on_opengl_by_choice()
		var eng := UI2.body(gx, "Graphics engine: %s" % ("OpenGL (compatibility)" if on_gl else "Vulkan"), 13, Color.WHITE)
		eng.set_meta("action_key", "gfx_engine")
		if on_gl and not by_file:
			UI2.body(gx, "This phone can't run Vulkan, so it uses OpenGL.", 11, UI2.MUTED)
		else:
			var to_gl := not on_gl
			UI2.button(gx, "SWITCH TO %s" % ("OPENGL" if to_gl else "VULKAN"), "blue", func():
				app.confirm("SWITCH GRAPHICS", "The game restarts and runs on %s. Use OpenGL if the game freezes or crashes on this phone." % ("OpenGL" if to_gl else "Vulkan"),
					"RESTART", "primary", func(): guard.set_opengl(to_gl)), "gfx_switch", 16, 44.0)
			UI2.body(gx, "Pick OpenGL if the game freezes on this phone. Switching restarts the game.", 11, UI2.MUTED)
	# Old progress
	var mig: Dictionary = d.migration
	var old := UI2.frame(root, "parch", 12, 16.0, "brown")
	var oh := UI.row(old, 8)
	UI2.icon(oh, "scroll", 36.0)
	UI.grow(UI2.text(oh, "PROGRESS FROM THE OLD VERSION", 14, ink, ink, 0, false))
	if str(mig.get("from", "")) == "legacy":
		var w := int(mig.weapons)
		var c := int(mig.chests)
		var tl := UI.label(old, "Carried over: +%d gold, +%d gems, level %d (includes %d weapon%s and %d chest%s turned into gold)." % [int(mig.gold), int(mig.gems), int(mig.level), w, "" if w == 1 else "s", c, "" if c == 1 else "s"], 12, ink, UI.HEAVY_FONT)
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	else:
		UI.label(old, "Played the previous Fatebound? Paste your exported progress to carry over gold, tokens (as gems) and your level. This works once.", 12, ink, UI.HEAVY_FONT)
		var te := TextEdit.new()
		te.custom_minimum_size = Vector2(0, 80)
		te.placeholder_text = "Paste exported progress here"
		te.set_meta("action_key", "import_text")
		old.add_child(te)
		UI2.button(old, "IMPORT", "blue", func():
			var v: Variant = JSON.parse_string(te.text.strip_edges())
			if not (v is Dictionary) or not (v as Dictionary).has("gold"):
				app.sfx("error")
				app.toast("That doesn't look like exported Fatebound progress", UI.RED)
				return
			var r: Dictionary = p.import_legacy(v)
			if r.ok:
				p.save()
				app.sfx("purchase")
				app.toast("Imported: +%d gold, +%d gems" % [int(r.summary.gold), int(r.summary.gems)], UI.GOLD)
			else:
				app.toast(str(r.error), UI.RED)
			app.rebuild(), "import_legacy", 16, 44.0)
	# Help
	var help := HBoxContainer.new()
	help.add_theme_constant_override("separation", 10)
	root.add_child(help)
	if Diag.has_logs():
		UI.grow(UI2.button(help, "COPY DIAGNOSTICS", "blue", func():
			DisplayServer.clipboard_set(Diag.read_logs())
			app.toast("Diagnostics copied", UI.CYAN), "copy_diag", 13, 40.0))
	UI.grow(UI2.button(help, "PRIVACY POLICY", "blue", func(): OS.shell_open(PRIVACY_URL), "privacy", 13, 40.0))
	var ver := UI2.body(root, "Fatebound %s" % Diag.BUILD, 11, UI2.MUTED)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
