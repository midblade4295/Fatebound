extends RefCounted
# Screens for the Siege app shell. Each builds into `root` from app.profile; the shell rebuilds
# the current screen after every change (buy, claim, equip...).
const UI = preload("res://scripts/app/ui.gd")
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

static func reward_text(r: Dictionary) -> Array:
	# -> [glyph kind, text, colour, texture path or ""]
	if r.has("item"):
		var it := Eco.item(str(r.item))
		return [item_icon(it), str(it.get("name", "?")), rarity(it), item_texture_path(str(r.item))]
	if r.has("gems"):
		return ["gem", "%d gems" % int(r.gems), UI.CYAN, "res://assets/ui/currency/gem.png"]
	var g := int(r.get("gold", 0))
	return ["coin", "%d gold" % g, UI.GOLD, "res://assets/ui/currency/%s.png" % ("coins_s" if g >= 300 else "coin")]

static func pack_list(app, root: Node) -> void:
	# One card per pack: name, the items' icons, and a gem button (the price covers only what the
	# player doesn't own yet).
	var p = app.profile
	for pid in Eco.PACKS:
		var pk: Dictionary = Eco.PACKS[pid]
		var c := UI.card(root)
		var row := UI.row(c, 10)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(v)
		UI.label(v, str(pk.name).to_upper(), 17, Color(Eco.RARITY_COLOR.get(str(pk.rarity), "#ffffff")))
		var icons := UI.row(v, 6)
		for id in pk.items:
			var it := Eco.item(id)
			var ic := item_icon(it)
			if ic != "":
				var t := UI.tex_icon(icons, ic, 44)
				t.modulate = Color(1, 1, 1, 0.45) if p.owns(id) else Color.WHITE
		var names := []
		for id in pk.items:
			names.append(str(Eco.item(id).name))
		UI.label(v, " + ".join(names), 11, UI.MUTED)
		var gems := Eco.pack_price(pid, p.d.owned)
		if gems <= 0:
			UI.label(row, "OWNED", 14, UI.MUTED)
			continue
		var b := UI.button(row, "      %s" % UI.compact(gems), "premium", func(): buy_pack(app, pid), "buy_" + pid, 15, 14)
		UI.tex_icon(b, "res://assets/ui/currency/gem.png", 26).position = Vector2(10, 8)
		b.disabled = not p.can_afford({"gems": gems})

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

static func price_button(parent: Node, app, id: String) -> Button:
	var price := Eco.item_price(id)
	var gems: bool = price.has("gems")
	var amount: int = int(price.get("gems", price.get("gold", 0)))
	var b := UI.button(parent, "      %s" % UI.compact(amount), "premium" if gems else "gold", func(): buy(app, id), "buy_" + id, 15, 14)
	UI.tex_icon(b, "res://assets/ui/currency/%s.png" % ("gem" if gems else "coin"), 26).position = Vector2(10, 8)
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
static func home(app, root: VBoxContainer) -> void:
	var p = app.profile
	var d: Dictionary = p.d
	# The hero itself (backdrop, live 3D character, logo) is the app's full-bleed layer behind this
	# scroll area; here is the space it shows through, then the class picker.
	app.hero_show(app.home_class, p.look_for(app.home_class))
	if bool(app.get("safe_boot")):
		# 0.31.70: the last start never reached the menu, so this one skipped the live hero and the background
		# loading. Hand the tester the start-up log (phases, errors, logcat) to send.
		UI.spacer(root, 96.0)
		var sb := UI.card(root, Color(0.16, 0.05, 0.05, 0.94), UI.RED)
		var st := UI.label(sb, "SAFE START", 14, UI.RED, UI.HEAVY_FONT, true)
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var sx := UI.label(sb, "The game got stuck starting last time, so this start skipped the 3D hero. Please copy the diagnostics and send them to the developer.", 12, UI.TEXT)
		sx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sx.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UI.button(sb, "COPY DIAGNOSTICS", "primary", func():
			DisplayServer.clipboard_set(Diag.read_logs())
			app.toast("Diagnostics copied -- paste them to the developer", UI.CYAN), "copy_diag_boot", 13)
		UI.spacer(root, 60.0)
	else:
		UI.spacer(root, 322.0)
	var eq: Dictionary = d.equip[app.home_class]
	var cn := UI.title(root, str(Eco.CLASS_NAMES[app.home_class]).to_upper(), 28, UI.TEXT)
	cn.add_theme_constant_override("outline_size", 8)
	var gear_name := str(Eco.item(str(eq.weapon)).get("name", "Default gear"))
	var sl := UI.label(root, gear_name, 12, UI.GOLD, UI.HEAVY_FONT, true)
	if d.has("refund_note"):                              # 0.31.39: skins removed -- tell them once what came back
		var rn: Dictionary = d.refund_note
		app.toast("Skins have been retired -- refunded %s" % ", ".join([("%d gold" % int(rn.gold)) if int(rn.gold) > 0 else "", ("%d gems" % int(rn.gems)) if int(rn.gems) > 0 else ""].filter(func(x): return x != "")), UI.GOLD)
		d.erase("refund_note")
		p.save()
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var chips := UI.row(root, 6)
	for cls in Eco.CLASSES:
		var sel: bool = app.home_class == cls
		var cb := UI.button(chips, "", "gold" if sel else "ghost", func():
			app.home_class = cls
			app.sfx("tap")
			app.rebuild(), "home_" + cls, 12, 14)
		cb.custom_minimum_size = Vector2(0, 46)
		UI.grow(cb)
		var ci := UI.icon(cb, cls, 24, Color("#2e1d00") if sel else UI.TEXT)
		ci.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		ci.position -= Vector2(12, 12)

	# Mode + PLAY
	var modes := UI.row(root, 8)
	UI.grow(UI.button(modes, "VS BOTS", "gold" if not app.play_online else "ghost", func():
		app.play_online = false
		app.sfx("tap")
		app.rebuild(), "mode_bots", 14))
	UI.grow(UI.button(modes, "ONLINE 16v16", "gold" if app.play_online else "ghost", func():
		app.sfx("tap")
		if bool(app.get("update_required")):
			app.show_update_screen()       # 0.31.73: online is locked until the update is installed
			return
		app.play_online = true
		app.rebuild(), "mode_online", 14))
	if not bool(d.get("tutorial_done", false)):
		# First visit: the Herald offers the walkthrough (0.19.0).
		var tc := UI.card(root, Color(0.2, 0.14, 0.05, 0.9), UI.GOLD)
		var tr := UI.row(tc, 10)
		UI.icon(tr, "crown", 28, UI.GOLD)
		UI.grow(UI.label(tr, "New here? The Royal Herald will show you the ropes. (+%d gold)" % app.TUTORIAL_GOLD, 14, Color("#ffe4a8")))
		UI.button(tc, "PLAY TUTORIAL", "gold", func(): app.start_tutorial(), "tutorial_start", 15)
	UI.play_button(root, "PLAY", func(): app.start_match(app.play_online), "play")
	var hint_text := "Join the live 16 vs 16 battle on the Siege server" if app.play_online else "You and 15 bots vs 16 bots · works offline"
	if bool(app.get("update_required")):
		hint_text = "Update Fatebound to play online · VS BOTS works offline"
	elif app.play_online and bool(app.get("server_updating")):
		hint_text = "Servers are updating, try again in a few minutes"
	var hint := UI.label(root, hint_text, 12, UI.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.button(root, "HOW TO PLAY", "ghost", func(): app.start_tutorial(), "tutorial", 13)
	if str(d.first_win_day) != Eco.day_key(p.now()):
		var fw := UI.card(root, Color(0.35, 0.22, 0.05, 0.85), UI.GOLD)
		var fr := UI.row(fw, 10)
		UI.icon(fr, "trophy", 28, UI.GOLD)
		UI.grow(UI.label(fr, "First win of the day: +%d gold  +%d pass XP  + a Silver Chest" % [Eco.FIRST_WIN.gold, Eco.FIRST_WIN.pass], 14, Color("#ffe4a8")))

	chests_card(app, root)

	# Siege Pass summary
	var pc := UI.card(root)
	var ph := UI.row(pc, 8)
	UI.icon(ph, "pass", 22, UI.GOLD)
	UI.grow(UI.label(ph, "SIEGE PASS", 16, UI.GOLD, UI.TITLE_FONT, true))
	var ends: int = Eco.season_ends(int(d.pass.season)) - p.now()
	UI.label(ph, "Season %d · %s left" % [int(d.pass.season), UI.duration(ends)], 11, UI.MUTED).autowrap_mode = TextServer.AUTOWRAP_OFF
	var tier: int = p.pass_tier()
	var tr := UI.row(pc, 10)
	var tl := UI.label(tr, "TIER %d" % tier, 26, UI.TEXT, UI.TITLE_FONT, true)
	tl.autowrap_mode = TextServer.AUTOWRAP_OFF
	var tv := VBoxContainer.new()
	UI.grow(tv)
	tr.add_child(tv)
	var in_tier: int = int(d.pass.xp) - tier * Eco.TIER_XP
	UI.label(tv, Eco.season_name(int(d.pass.season)) if tier < Eco.PASS_TIERS else "Pass complete!", 12, UI.MUTED)
	UI.progress(tv, in_tier if tier < Eco.PASS_TIERS else 1, Eco.TIER_XP if tier < Eco.PASS_TIERS else 1, UI.GOLD, 12)
	var claimable := 0
	for t in range(1, tier + 1):
		for prem in [false, true]:
			if p.can_claim(t, prem):
				claimable += 1
	UI.button(pc, "CLAIM %d REWARD%s" % [claimable, "" if claimable == 1 else "S"] if claimable > 0 else "VIEW PASS", "claim" if claimable > 0 else "secondary", func(): app.show_tab("pass"), "go_pass", 14)

	# Challenges
	challenges_card(app, root, "daily")
	challenges_card(app, root, "weekly")

# ---------- chests (0.31.37) ----------
static func chests_card(app, root: Node) -> void:
	var p = app.profile
	var c := UI.card(root)
	var h := UI.row(c, 8)
	UI.icon(h, "chest", 22, UI.GOLD)
	UI.grow(UI.label(h, "CHESTS", 16, UI.GOLD, UI.TITLE_FONT, true))
	UI.label(h, "%d/%d" % [p.chests().size(), Eco.CHEST_SLOTS], 12, UI.MUTED).autowrap_mode = TextServer.AUTOWRAP_OFF
	var slots := UI.row(c, 8)
	var busy: Dictionary = p.unlocking()
	for i in Eco.CHEST_SLOTS:
		var cell := UI.card(slots, Color(0.1, 0.09, 0.12, 0.9), Color(0.3, 0.27, 0.22))
		cell.custom_minimum_size = Vector2(0, 118)
		UI.grow(cell)
		if i >= p.chests().size():
			var e := UI.label(cell, "Win to earn chests", 10, UI.MUTED)
			e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			continue
		var ch: Dictionary = p.chests()[i]
		var def: Dictionary = Eco.CHESTS[str(ch.kind)]
		var col := Color(str(def.color))
		var ic := UI.icon(cell, "chest", 34, col)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var nm := UI.label(cell, str(def.name).replace(" Chest", ""), 11, col, UI.HEAVY_FONT, true)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var idx := i
		if p.chest_ready(ch):
			UI.button(cell, "OPEN", "claim", func(): open_chest(app, idx), "chest_open_%d" % i, 12)
		elif int(ch.start) >= 0:
			var t := UI.label(cell, UI.duration(p.chest_left(ch)), 11, UI.TEXT)
			t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			UI.button(cell, "%d 💎" % Eco.skip_cost(p.chest_left(ch)), "secondary", func(): skip_chest(app, idx), "chest_skip_%d" % i, 11)
		elif busy.is_empty():
			UI.button(cell, "UNLOCK\n%s" % UI.duration(p.chest_left(ch)), "secondary", func():
				p.start_unlock(idx)
				app.sfx("tap")
				app.rebuild(), "chest_unlock_%d" % i, 10)
		else:
			var w := UI.label(cell, UI.duration(p.chest_left(ch)), 10, UI.MUTED)
			w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			UI.button(cell, "%d 💎" % Eco.skip_cost(p.chest_left(ch)), "ghost", func(): skip_chest(app, idx), "chest_skip_%d" % i, 11)
	var odds := UI.label(c, "One chest unlocks at a time. Tap a chest's gems to open it now. Chests are earned by playing -- never sold.", 10, UI.MUTED)
	odds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UI.button(c, "WHAT'S INSIDE?", "ghost", func(): chest_odds(app), "chest_odds", 11)

static func skip_chest(app, idx: int) -> void:
	var r: Dictionary = app.profile.skip_chest(idx)
	if bool(r.get("ok", false)):
		app.sfx("tap")
		open_chest(app, idx)
	else:
		app.sfx("error")
		app.toast("Not enough gems (%d needed)" % int(r.get("cost", 0)), UI.RED)

static func open_chest(app, idx: int) -> void:
	var r: Dictionary = app.profile.open_chest(idx)
	if not bool(r.get("ok", false)):
		return
	app.sfx("purchase")
	var parts := ["+%d gold" % int(r.gold)]
	if int(r.gems) > 0:
		parts.append("+%d gems" % int(r.gems))
	if str(r.item) != "":
		parts.append(str(Eco.item(str(r.item)).get("name", "a cosmetic")) + " (%s)" % str(Eco.item(str(r.item)).get("rarity", "")))
	if int(r.dupe_gold) > 0:
		parts.append("duplicate -> +%d gold" % int(r.dupe_gold))
	app.toast("%s: %s" % [str(Eco.CHESTS[str(r.kind)].name), "  ·  ".join(parts)], UI.GOLD)
	app.rebuild()

static func chest_odds(app) -> void:
	var lines := []
	for k in ["wooden", "silver", "gold", "royal"]:
		lines.append("%s (%s): %s" % [str(Eco.CHESTS[k].name), UI.duration(int(Eco.CHESTS[k].unlock)), Eco.chest_odds(k)])
	app.toast("\n".join(lines), UI.TEXT)

static func challenges_card(app, root: Node, span: String) -> void:
	var p = app.profile
	var list: Array = p.d.challenges.daily if span == "daily" else p.d.challenges.weekly
	var c := UI.card(root)
	var now: int = p.now()
	var reset: int = (int(floor(now / 86400.0)) + 1) * 86400 - now if span == "daily" else 0
	if span == "weekly":
		var days := int(floor(now / 86400.0))
		var monday := days - ((days + 3) % 7)
		reset = (monday + 7) * 86400 - now
	section(c, "DAILY CHALLENGES" if span == "daily" else "WEEKLY CHALLENGES", "resets in " + UI.duration(reset), "clock")
	for i in list.size():
		var ch: Dictionary = list[i]
		var def: Dictionary = Eco.CHALLENGES[ch.id]
		var row := UI.row(c, 10)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 3)
		UI.grow(v)
		row.add_child(v)
		UI.label(v, str(def.text), 13, UI.TEXT)
		var reward := "+%d pass XP" % int(def.pass)
		if def.has("gold"):
			reward += " · +%d gold" % int(def.gold)
		if def.has("gems"):
			reward += " · +%d gems" % int(def.gems)
		var pr := UI.row(v, 6)
		UI.grow(UI.progress(pr, int(ch.progress), int(def.goal), UI.CYAN if not bool(ch.claimed) else UI.GREEN, 9))
		UI.label(pr, "%d/%d" % [int(ch.progress), int(def.goal)], 11, UI.MUTED).autowrap_mode = TextServer.AUTOWRAP_OFF
		UI.label(v, reward, 11, UI.GOLD)
		var done: bool = int(ch.progress) >= int(def.goal)
		if bool(ch.claimed):
			UI.icon(row, "check", 26, UI.GREEN)
		elif done:
			UI.button(row, "CLAIM", "claim", func():
				var r: Dictionary = p.claim_challenge(span, i)
				if r.ok:
					app.sfx("coin")
					app.toast("Challenge complete!" + (" Pass tier %d reached" % int(r.tiers[-1]) if not r.tiers.is_empty() else ""), UI.GREEN)
				app.rebuild(), "claim_%s_%d" % [span, i], 13)
		elif span == "daily" and not bool(p.d.challenges.rerolled):
			UI.button(row, "↻", "ghost", func():
				if p.reroll_daily(i):
					app.sfx("flip")
				app.rebuild(), "reroll_%d" % i, 16, 12)

# ---------------- PASS ----------------
static func pass_screen(app, root: VBoxContainer) -> void:
	# 0.31.42 (Kevin): a richer Siege Pass -- season banner, a big tier medallion and XP bar, the premium offer with what
	# it holds, the season's best item turning in 3D at the top, then the track: free on the left, premium on the right,
	# a gold spine through the tiers. Tap any reward for the detail view (3D, turn it with a finger).
	var p = app.profile
	var d: Dictionary = p.d
	var sid: int = int(d.pass.season)
	var tier: int = p.pass_tier()
	var items: Array = Eco.pass_items(sid)

	# --- banner
	var ban := _panel(root, Color("#1d1233"), PASS_GOLD, 22, Color(0.55, 0.35, 0.95, 0.45), 16)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 6)
	ban.add_child(bv)
	var top := UI.row(bv, 8)
	_chip(top, "SEASON %d" % sid, PASS_GOLD, Color("#2e1d00"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	_chip(top, "ENDS IN %s" % UI.duration(Eco.season_ends(sid) - p.now()).to_upper(), Color(1, 1, 1, 0.1), UI.TEXT)
	var sn := UI.label(bv, str(Eco.season_name(sid)).to_upper(), 30, PASS_GOLD, UI.TITLE_FONT, true)
	sn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := UI.label(bv, "SIEGE PASS", 13, Color("#c9b6ff"), UI.HEAVY_FONT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tr := UI.row(bv, 12)
	var med := _panel(tr, Color("#2b1a4a"), PASS_GOLD, 40, Color(1.0, 0.8, 0.3, 0.35), 0)
	med.custom_minimum_size = Vector2(78, 78)
	med.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var mc := CenterContainer.new()
	med.add_child(mc)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", -6)
	mc.add_child(mv)
	var tl := UI.label(mv, "TIER", 10, Color("#c9b6ff"), UI.HEAVY_FONT)
	tl.autowrap_mode = TextServer.AUTOWRAP_OFF
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tn := UI.label(mv, str(tier), 34, PASS_GOLD, UI.TITLE_FONT, true)
	tn.autowrap_mode = TextServer.AUTOWRAP_OFF
	tn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var xv := VBoxContainer.new()
	xv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xv.alignment = BoxContainer.ALIGNMENT_CENTER
	tr.add_child(xv)
	if tier < Eco.PASS_TIERS:
		UI.label(xv, "NEXT: TIER %d" % (tier + 1), 13, UI.TEXT, UI.HEAVY_FONT)
		UI.progress(xv, int(d.pass.xp) - tier * Eco.TIER_XP, Eco.TIER_XP, PASS_GOLD, 16)
		UI.label(xv, "%d / %d XP" % [int(d.pass.xp) - tier * Eco.TIER_XP, Eco.TIER_XP], 11, UI.MUTED)
	else:
		UI.label(xv, "PASS COMPLETE", 16, PASS_GOLD, UI.HEAVY_FONT)

	# --- premium
	var legendary := 0
	for k in range(Eco.PASS_FREE_ITEMS, items.size()):
		if str(Eco.CATALOG[items[k]].rarity) == "legendary":
			legendary += 1
	if bool(d.pass.premium):
		var pa := _panel(root, Color("#2a1650"), PASS_PURPLE, 16, Color(0.7, 0.45, 1.0, 0.35), 10)
		var pr := UI.row(pa, 10)
		UI.icon(pr, "crown", 26, PASS_GOLD)
		UI.grow(UI.label(pr, "PREMIUM ACTIVE -- all %d premium rewards are yours to claim" % Eco.PASS_TIERS, 13, Color("#e6d6ff"), UI.HEAVY_FONT))
	else:
		var pc := _panel(root, Color("#2a1650"), PASS_PURPLE, 20, Color(0.7, 0.45, 1.0, 0.5), 14)
		var pv := VBoxContainer.new()
		pv.add_theme_constant_override("separation", 8)
		pc.add_child(pv)
		var ph := UI.row(pv, 10)
		UI.icon(ph, "crown", 30, PASS_GOLD)
		var pt := VBoxContainer.new()
		pt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ph.add_child(pt)
		UI.label(pt, "UNLOCK PREMIUM", 18, PASS_GOLD, UI.TITLE_FONT, true)
		UI.label(pt, "%d exclusive cosmetics (%d legendary) · gold chests · a Royal chest · more gems on every tier" % [Eco.PASS_PREMIUM_ITEMS, legendary], 12, Color("#e6d6ff"))
		var b := UI.button(pv, "UNLOCK  ·  %d GEMS" % Eco.PREMIUM_COST, "premium", func(): _buy_premium(app), "buy_premium", 16)
		b.disabled = int(d.gems) < Eco.PREMIUM_COST
		var gl := UI.label(pv, "You have %d gems" % int(d.gems), 11, UI.MUTED)
		gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# --- the season's best: premium tier 30, turning
	var best: String = str(items[items.size() - 1])
	var fc := _panel(root, Color("#120c22"), Color(Eco.RARITY_COLOR.get(str(Eco.CATALOG[best].rarity), "#ffffff")), 18, Color(1.0, 0.75, 0.3, 0.3), 0)
	fc.custom_minimum_size = Vector2(0, 230)
	var stage := Control.new()
	stage.clip_contents = true
	fc.add_child(stage)
	if str(Eco.CATALOG[best].kind) == "weapon":
		Showcase.backdrop(stage)
		var sh := Showcase.new()
		sh.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stage.add_child(sh)
		sh.show_look(str(Eco.CATALOG[best]["class"]), {"r": str(Eco.CATALOG[best].get("r", "")), "l": str(Eco.CATALOG[best].get("l", ""))})
	var cap := VBoxContainer.new()
	cap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	cap.offset_top = -64
	cap.offset_left = 14
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(cap)
	_chip(cap, "TIER 30 · PREMIUM · %s" % str(Eco.CATALOG[best].rarity).to_upper(), PASS_PURPLE, Color.WHITE)
	UI.label(cap, str(Eco.CATALOG[best].name), 20, Color.WHITE, UI.TITLE_FONT, true)
	var tap := Button.new()
	tap.flat = true
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
		UI.button(root, "CLAIM ALL  (%d)" % claimable, "claim", func():
			var got: Array = p.claim_all()
			app.sfx("coin")
			app.toast("Claimed %d reward%s" % [got.size(), "" if got.size() == 1 else "s"], UI.GREEN)
			app.rebuild(), "claim_all", 16)

	# --- the track
	var head := UI.row(root, 0)
	var hf := UI.label(head, "FREE", 13, UI.MUTED, UI.HEAVY_FONT)
	hf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hf.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(46, 0)
	head.add_child(gap)
	var hp := UI.label(head, "PREMIUM", 13, PASS_PURPLE, UI.HEAVY_FONT)
	hp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(46, 0)
	col.add_theme_constant_override("separation", 0)
	row.add_child(col)
	var reached := t <= tier
	for part in ["top", "medal", "bottom"]:
		if part == "medal":
			var m := PanelContainer.new()
			var sb := StyleBoxFlat.new()
			sb.bg_color = PASS_GOLD if reached else Color("#1b2236")
			sb.border_color = PASS_GOLD if reached else Color(1, 1, 1, 0.18)
			sb.set_border_width_all(2)
			sb.set_corner_radius_all(20)
			if reached:
				sb.shadow_color = Color(1.0, 0.8, 0.3, 0.45)
				sb.shadow_size = 6
			m.add_theme_stylebox_override("panel", sb)
			m.custom_minimum_size = Vector2(38, 38)
			m.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			col.add_child(m)
			var l := UI.label(m, str(t), 15, Color("#2e1d00") if reached else UI.MUTED, UI.HEAVY_FONT)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		else:
			var line := ColorRect.new()
			var lit := reached if part == "top" else t < tier
			line.color = PASS_GOLD if lit else Color(1, 1, 1, 0.1)
			line.custom_minimum_size = Vector2(4, 0)
			line.size_flags_vertical = Control.SIZE_EXPAND_FILL
			line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			col.add_child(line)

static func pass_cell(app, parent: Node, sid: int, t: int, prem: bool) -> void:
	var p = app.profile
	var r: Dictionary = Eco.pass_reward(sid, t, prem)
	var rt: Array = reward_text(r)
	var it: Dictionary = Eco.item(str(r.get("item", "")))
	var claimed: bool = (p.d.pass.prem if prem else p.d.pass.free).has(t)
	var ready: bool = p.can_claim(t, prem)
	var locked_prem: bool = prem and not bool(p.d.pass.premium)
	var locked: bool = t > p.pass_tier()
	var edge: Color = rt[2] if not it.is_empty() else (PASS_PURPLE if prem else Color(1, 1, 1, 0.16))
	var fill := Color("#221640") if prem else Color("#131c2e")
	var glow := Color(0, 0, 0, 0)
	if ready:
		edge = UI.GREEN
		glow = Color(0.37, 0.86, 0.53, 0.5)
	elif not it.is_empty() and str(it.rarity) in ["epic", "legendary"]:
		glow = Color(edge.r, edge.g, edge.b, 0.35)
	var cell := _panel(parent, fill, edge, 14, glow, 6)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.custom_minimum_size = Vector2(0, 104 if ready else 92)
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(0, 92 if ready else 80)
	cell.add_child(stack)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if ready:
		v.offset_bottom = -24                            # room for the CLAIM button under it
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(v)
	var ic := CenterContainer.new()
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ic)
	if str(rt[3]) != "":
		UI.tex_icon(ic, str(rt[3]), 48)
	else:
		UI.icon(ic, str(rt[0]), 30, rt[2])
	var nm := UI.label(v, str(rt[1]), 10, UI.TEXT, UI.HEAVY_FONT)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_OFF
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if not it.is_empty():
		var rl := UI.label(v, str(it.rarity).to_upper(), 8, rt[2], UI.HEAVY_FONT)
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if claimed or locked or locked_prem:
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.45)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(dim)
		var badge := CenterContainer.new()
		badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		badge.position += Vector2(-22, 2)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(badge)
		UI.icon(badge, "check" if claimed else "lock", 18, UI.GREEN if claimed else (PASS_PURPLE if locked_prem else UI.MUTED))
	var tap := Button.new()
	tap.flat = true
	tap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tap.pressed.connect(func(): open_pass_item(app, sid, t, prem))
	stack.add_child(tap)
	if ready:
		var gb := UI.button(stack, "CLAIM", "claim", func(): _claim_tier(app, t, prem), "claim_%s_%d" % ["prem" if prem else "free", t], 10, 10)
		gb.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		gb.offset_top = -22
		gb.offset_left = 10
		gb.offset_right = -10
		gb.custom_minimum_size = Vector2(0, 20)

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
	var p = app.profile
	var now: int = p.now()
	UI.title(root, "SHOP", 26)
	var note := UI.label(root, "Everything here is cosmetic. Your class still comes from the hat machines.", 12, UI.MUTED)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var days := int(floor(now / 86400.0))
	var monday := days - ((days + 3) % 7)
	section(root, "FEATURED", "new in " + UI.duration((monday + 7) * 86400 - now), "crown")
	item_grid(app, root, Eco.shop_featured(now), true)
	section(root, "PACKS", "skin + weapon bundles", "crown")
	pack_list(app, root)
	section(root, "DAILY DEALS", "new in " + UI.duration((days + 1) * 86400 - now), "clock")
	item_grid(app, root, Eco.shop_daily(now), false)
	section(root, "GEMS → GOLD", "", "coin")
	var ex := UI.row(root, 8)
	for off in Eco.EXCHANGE:
		var c := UI.card(ex)
		(c.get_parent() as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pile := UI.tex_icon(c, "res://assets/ui/currency/coins_%s.png" % str(off.id).substr(5), 78)
		pile.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var gl := UI.label(c, UI.compact(int(off.gold)) + " gold", 15, UI.GOLD, UI.HEAVY_FONT, true)
		gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var oid: String = off.id
		var b := UI.button(c, "     %d" % int(off.gems), "premium", func():
			var r: Dictionary = p.exchange(oid)
			if r.ok:
				app.sfx("coin")
				app.toast("+%s gold" % UI.compact(int(off.gold)), UI.GOLD)
			else:
				app.sfx("error")
				app.toast(str(r.error), UI.RED)
			app.rebuild(), "exchange_" + oid, 14, 12)
		UI.tex_icon(b, "res://assets/ui/currency/gem.png", 24).position = Vector2(8, 7)
		b.disabled = int(p.d.gems) < int(off.gems)

static func item_grid(app, root: Node, ids: Array, big: bool) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	root.add_child(grid)
	for id in ids:
		var it := Eco.item(id)
		var p = app.profile
		var cardp := PanelContainer.new()
		var sb := UI.card_style(UI.CARD, 16, rarity(it))
		sb.set_border_width_all(2)
		cardp.add_theme_stylebox_override("panel", sb)
		UI.grow(cardp)
		grid.add_child(cardp)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		cardp.add_child(v)
		var sw := CenterContainer.new()
		v.add_child(sw)
		item_swatch(sw, id, 100 if big else 80)
		var n := UI.label(v, str(it.name), 14, UI.TEXT, UI.HEAVY_FONT, true)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var k := UI.label(v, item_kind_text(it), 11, UI.MUTED)
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var rl := UI.label(v, str(it.rarity).to_upper(), 10, rarity(it), UI.HEAVY_FONT)
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if p.owns(id):
			var equipped: bool = is_equipped(p, id)
			UI.button(v, "EQUIPPED" if equipped else "EQUIP", "ghost" if equipped else "secondary", func(): equip(app, id), "equip_" + id, 13, 12).disabled = equipped
		else:
			price_button(v, app, id)

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
static func locker(app, root: VBoxContainer) -> void:
	var p = app.profile
	UI.title(root, "LOCKER", 26)
	var tabs := UI.row(root, 6)
	for cls in Eco.CLASSES + ["titles"]:
		var sel: bool = app.locker_class == cls
		var b := UI.button(tabs, "", "gold" if sel else "ghost", func():
			app.locker_class = cls
			app.sfx("tap")
			app.rebuild(), "locker_" + cls, 12, 12)
		b.custom_minimum_size = Vector2(0, 48)
		UI.grow(b)
		var ic := UI.icon(b, "title" if cls == "titles" else cls, 24, Color("#2e1d00") if sel else UI.TEXT)
		ic.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		ic.position -= Vector2(12, 14)
	# 0.31.38: the upgraded classes, a second row -- their base class's icon in gold, the name under it
	var uptabs := UI.row(root, 6)
	for ucls in Eco.UP_CLASSES:
		var usel: bool = app.locker_class == ucls
		var ub := UI.button(uptabs, "", "gold" if usel else "ghost", func():
			app.locker_class = ucls
			app.sfx("tap")
			app.rebuild(), "locker_" + ucls, 9, 12)
		ub.custom_minimum_size = Vector2(0, 56)
		UI.grow(ub)
		var uic := UI.icon(ub, str(Eco.UP_BASE[ucls]), 22, Color("#2e1d00") if usel else UI.GOLD)
		uic.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		uic.position += Vector2(-11, 7)
		var short := {"crusader":"CRUSADER", "berserker":"BERSERK", "necromancer":"NECRO", "assassin":"ASSASSIN", "sniper":"RANGER", "archmage":"ARCHMAGE"}
		var ul := UI.label(ub, str(short[ucls]), 8, Color("#2e1d00") if usel else UI.TEXT, UI.HEAVY_FONT)
		ul.autowrap_mode = TextServer.AUTOWRAP_OFF
		ul.clip_text = true
		ul.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ul.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		ul.offset_left = 2
		ul.offset_right = -2
		ul.offset_top = -17
		ul.offset_bottom = -4
	if app.locker_class == "titles":
		section(root, "TITLES", "shown next to your name", "title")
		var none := UI.card(root)
		var nr := UI.row(none, 8)
		UI.grow(UI.label(nr, "No title", 14, UI.TEXT))
		UI.button(nr, "EQUIPPED" if str(p.d.title) == "" else "EQUIP", "ghost" if str(p.d.title) == "" else "secondary", func():
			p.unequip("", "title")
			app.rebuild(), "equip_default_title", 12, 12).disabled = str(p.d.title) == ""
		for id in Eco.CATALOG:
			if Eco.CATALOG[id].kind == "title":
				locker_row(app, root, id)
		return
	var cls: String = app.locker_class
	var hero := PanelContainer.new()
	var hs := UI.card_style(Color(0.05, 0.09, 0.16, 1.0), 22, UI.CARD_HI)
	for side in ["left", "right", "top", "bottom"]:
		hs.set("content_margin_" + side, 0.0)
	hero.add_theme_stylebox_override("panel", hs)
	hero.custom_minimum_size = Vector2(0, 280)
	root.add_child(hero)
	var stage := Control.new()
	stage.clip_contents = true
	hero.add_child(stage)
	Showcase.backdrop(stage)
	var show := Showcase.new()
	show.interactive = true                                  # 0.31.64 (Kevin): turn and zoom the hero in the locker too
	show.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(show)
	show.show_look(cls, p.look_for(cls))
	zoom_controls(stage, show, "locker")
	var nm := UI.title(root, str(Eco.CLASS_NAMES[cls]).to_upper(), 20, UI.TEXT)
	for slot in ["weapon"]:                                 # 0.31.39: weapons are the only class cosmetic
		section(root, "SKINS" if slot == "skin" else "WEAPONS", "", "skin" if slot == "skin" else "weapon")
		var def := UI.card(root)
		var dr := UI.row(def, 10)
		var dtex := UI.tex(("res://assets/ui/skins/default_%s.png" if slot == "skin" else "res://assets/ui/icons/default_%s.png") % cls)
		swatch(dr, dtex, UI.CARD_HI, 60, "star")
		UI.grow(UI.label(dr, "Default " + ("look" if slot == "skin" else "gear"), 14, UI.TEXT, UI.HEAVY_FONT))
		var is_def: bool = str(p.d.equip[cls][slot]) == ""
		UI.button(dr, "EQUIPPED" if is_def else "EQUIP", "ghost" if is_def else "secondary", func():
			p.unequip(cls, slot)
			app.sfx("equip")
			app.rebuild(), "equip_default_%s_%s" % [cls, slot], 12, 12).disabled = is_def
		for id in Eco.CATALOG:
			var it: Dictionary = Eco.CATALOG[id]
			if it.kind == slot and str(it["class"]) == cls:
				locker_row(app, root, id)

# + / − zoom buttons and the hint over an interactive showcase (the pass item view, 0.31.48; the locker, 0.31.64)
static func zoom_controls(stage: Control, sh, prefix: String) -> void:
	var zc := VBoxContainer.new()
	zc.add_theme_constant_override("separation", 8)
	zc.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	zc.offset_left = -58
	zc.offset_right = -10
	zc.offset_top = -52
	zc.offset_bottom = 52
	stage.add_child(zc)
	for zb in [["+", 1.3, prefix + "_zoom_in"], ["−", 1.0 / 1.3, prefix + "_zoom_out"]]:
		var zf: float = zb[1]
		var b := UI.button(zc, str(zb[0]), "ghost", func(): sh.zoom_by(zf), str(zb[2]), 22, 14)
		b.custom_minimum_size = Vector2(46, 46)
	var hint := UI.label(stage, "DRAG TO TURN  ·  PINCH TO ZOOM", 11, Color(1, 1, 1, 0.8), UI.HEAVY_FONT)
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -28
	hint.offset_bottom = -8
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE

static func locker_row(app, root: Node, id: String) -> void:
	var p = app.profile
	var it := Eco.item(id)
	var c := UI.card(root)
	var r := UI.row(c, 10)
	item_swatch(r, id, 64)
	var v := VBoxContainer.new()
	UI.grow(v)
	r.add_child(v)
	UI.label(v, str(it.name), 14, UI.TEXT, UI.HEAVY_FONT)
	UI.label(v, str(it.rarity).to_upper(), 10, rarity(it), UI.HEAVY_FONT)
	if p.owns(id):
		var eq: bool = is_equipped(p, id)
		UI.button(r, "EQUIPPED" if eq else "EQUIP", "ghost" if eq else "secondary", func(): equip(app, id), "equip_" + id, 12, 12).disabled = eq
		return
	var where := "Siege Pass reward"
	if str(it.get("source", "")) == "shop":
		var now: int = p.now()
		where = "In the shop today" if (Eco.shop_daily(now).has(id) or Eco.shop_featured(now).has(id)) else "Rotates through the shop"
	UI.label(v, where, 11, UI.MUTED)
	UI.icon(r, "lock", 20, UI.MUTED)
	c.get_parent().modulate.a = 0.7

# ---------------- SETTINGS ----------------
static func settings(app, root: VBoxContainer) -> void:
	var p = app.profile
	var d: Dictionary = p.d
	UI.title(root, "SETTINGS", 26)
	# Profile
	var prof := UI.card(root)
	section(prof, "PROFILE", "", "locker")
	var nr := UI.row(prof, 8)
	var name_edit := LineEdit.new()
	name_edit.text = str(d.name)
	name_edit.max_length = 24          # capped to 16 after trimming spaces (see SAVE)
	name_edit.placeholder_text = "Your name"
	name_edit.add_theme_font_override("font", UI.HEAVY_FONT)
	name_edit.add_theme_font_size_override("font_size", 15)
	name_edit.add_theme_stylebox_override("normal", UI.card_style(Color(0, 0, 0, 0.4), 10, UI.CARD_HI, false))
	UI.grow(name_edit)
	nr.add_child(name_edit)
	UI.button(nr, "SAVE", "secondary", func():
		var nm := name_edit.text.strip_edges().left(16)
		if nm == "":
			nm = "Player"
		d.name = nm
		p.save()
		app.sfx("confirm")
		app.toast("Name saved", UI.CYAN)
		app.refresh_top(), "save_name", 13, 12)
	var st: Dictionary = d.stats
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	prof.add_child(grid)
	for pair in [["Matches", st.matches], ["Wins", st.wins], ["King rescues", st.rescues], ["Knockouts", st.kills],
			["Gate damage", int(st.gates) * 100], ["Gathered", st.gathered], ["Fish fed", st.fed], ["Level", d.level]]:
		var kl := UI.label(grid, str(pair[0]), 12, UI.MUTED)
		kl.autowrap_mode = TextServer.AUTOWRAP_OFF
		UI.grow(kl)
		var vl := UI.label(grid, UI.compact(int(pair[1])), 13, UI.TEXT, UI.HEAVY_FONT)
		vl.autowrap_mode = TextServer.AUTOWRAP_OFF
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Audio + graphics
	var au := UI.card(root)
	section(au, "SOUND & DISPLAY", "", "gear")
	for pair in [["master", "Master volume"], ["sfx", "Effects"], ["music", "Music"]]:
		var key: String = pair[0]
		UI.label(au, str(pair[1]), 12, UI.MUTED)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = float(d.settings.get(key, 0.6 if key == "music" else 0.8))
		sl.set_meta("action_key", "slider_" + key)
		sl.value_changed.connect(func(v: float):
			d.settings[key] = v
			p.save()
			app._apply_audio())
		au.add_child(sl)
	var rm := CheckButton.new()
	rm.text = "Reduce effects (smoother on older phones)"
	rm.button_pressed = bool(d.settings.get("reduce_motion", false))
	rm.add_theme_font_override("font", UI.HEAVY_FONT)
	rm.add_theme_font_size_override("font_size", 13)
	rm.set_meta("action_key", "reduce_motion")
	rm.toggled.connect(func(on: bool):
		d.settings.reduce_motion = on
		p.save())
	au.add_child(rm)
	var hq := CheckButton.new()
	hq.text = "High-quality graphics (shadows, glow, smooth edges)"
	hq.button_pressed = bool(d.settings.get("hq_graphics", true))
	hq.add_theme_font_override("font", UI.HEAVY_FONT)
	hq.add_theme_font_size_override("font_size", 13)
	hq.set_meta("action_key", "hq_graphics")
	hq.toggled.connect(func(on: bool):
		d.settings.hq_graphics = on
		p.save())
	au.add_child(hq)
	# 0.31.72: the graphics engine. Vulkan by default; OpenGL when Godot finds no usable Vulkan, after a start on Vulkan
	# froze (BootGuard), or by choice here. Switching restarts the game.
	var guard = app.get_node_or_null("/root/BootGuard")
	if guard != null:
		var on_gl := RenderingServer.get_current_rendering_method() == "gl_compatibility"
		var by_file: bool = guard.on_opengl_by_choice()
		var eng := UI.label(au, "Graphics engine: %s" % ("OpenGL (compatibility)" if on_gl else "Vulkan"), 13, UI.TEXT, UI.HEAVY_FONT)
		eng.set_meta("action_key", "gfx_engine")
		if on_gl and not by_file:
			UI.label(au, "This phone can't run Vulkan, so it uses OpenGL.", 11, UI.MUTED)
		else:
			var to_gl := not on_gl
			UI.button(au, "SWITCH TO %s" % ("OPENGL" if to_gl else "VULKAN"), "secondary", func():
				app.confirm("SWITCH GRAPHICS", "The game restarts and runs on %s. Use OpenGL if the game freezes or crashes on this phone." % ("OpenGL" if to_gl else "Vulkan"),
					"RESTART", "primary", func(): guard.set_opengl(to_gl)), "gfx_switch", 13)

	# Old progress
	var mig: Dictionary = d.migration
	var old := UI.card(root)
	section(old, "PROGRESS FROM THE OLD VERSION", "", "chest")
	if str(mig.get("from", "")) == "legacy":
		var w := int(mig.weapons)
		var c := int(mig.chests)
		UI.label(old, "Carried over: +%d gold, +%d gems, level %d (includes %d weapon%s and %d chest%s turned into gold)." % [int(mig.gold), int(mig.gems), int(mig.level), w, "" if w == 1 else "s", c, "" if c == 1 else "s"], 12, UI.TEXT)
	else:
		UI.label(old, "Played the previous Fatebound? Paste your exported progress to carry over gold, tokens (as gems) and your level. This works once.", 12, UI.MUTED)
		var te := TextEdit.new()
		te.custom_minimum_size = Vector2(0, 80)
		te.placeholder_text = "Paste exported progress here"
		te.set_meta("action_key", "import_text")
		old.add_child(te)
		UI.button(old, "IMPORT", "secondary", func():
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
			app.rebuild(), "import_legacy", 13)
	# Help
	var help := UI.card(root)
	section(help, "HELP", "", "star")
	if Diag.has_logs():
		UI.button(help, "COPY DIAGNOSTICS", "secondary", func():
			DisplayServer.clipboard_set(Diag.read_logs())
			app.toast("Diagnostics copied", UI.CYAN), "copy_diag", 13)
	UI.button(help, "PRIVACY POLICY", "ghost", func(): OS.shell_open(PRIVACY_URL), "privacy", 13)
	var ver := UI.label(root, "Fatebound %s" % Diag.BUILD, 11, UI.MUTED)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
