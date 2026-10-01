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
	UI.spacer(root, 322.0)
	var eq: Dictionary = d.equip[app.home_class]
	var cn := UI.title(root, str(Eco.CLASS_NAMES[app.home_class]).to_upper(), 28, UI.TEXT)
	cn.add_theme_constant_override("outline_size", 8)
	var skin_name := str(Eco.item(str(eq.skin)).get("name", "Default look"))
	var sl := UI.label(root, skin_name, 12, UI.GOLD, UI.HEAVY_FONT, true)
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
		app.play_online = true
		app.sfx("tap")
		app.rebuild(), "mode_online", 14))
	if not bool(d.get("tutorial_done", false)):
		# First visit: the Herald offers the walkthrough (0.19.0).
		var tc := UI.card(root, Color(0.2, 0.14, 0.05, 0.9), UI.GOLD)
		var tr := UI.row(tc, 10)
		UI.icon(tr, "crown", 28, UI.GOLD)
		UI.grow(UI.label(tr, "New here? The Royal Herald will show you the ropes. (+%d gold)" % app.TUTORIAL_GOLD, 14, Color("#ffe4a8")))
		UI.button(tc, "PLAY TUTORIAL", "gold", func(): app.start_tutorial(), "tutorial_start", 15)
	UI.play_button(root, "PLAY", func(): app.start_match(app.play_online), "play")
	var hint := UI.label(root, "Join the live 16 vs 16 battle on the Siege server" if app.play_online else "You and 15 bots vs 16 bots · works offline", 12, UI.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.button(root, "HOW TO PLAY", "ghost", func(): app.start_tutorial(), "tutorial", 13)
	if str(d.first_win_day) != Eco.day_key(p.now()):
		var fw := UI.card(root, Color(0.35, 0.22, 0.05, 0.85), UI.GOLD)
		var fr := UI.row(fw, 10)
		UI.icon(fr, "trophy", 28, UI.GOLD)
		UI.grow(UI.label(fr, "First win of the day: +%d gold  +%d pass XP" % [Eco.FIRST_WIN.gold, Eco.FIRST_WIN.pass], 14, Color("#ffe4a8")))

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
	var p = app.profile
	var d: Dictionary = p.d
	var sid: int = int(d.pass.season)
	var head := UI.card(root, Color(0.12, 0.08, 0.2, 0.95), UI.PURPLE)
	UI.title(head, "SIEGE PASS", 26)
	var sn := UI.label(head, "Season %d · %s · ends in %s" % [sid, Eco.season_name(sid), UI.duration(Eco.season_ends(sid) - p.now())], 12, UI.MUTED)
	sn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tier: int = p.pass_tier()
	var tr := UI.row(head, 10)
	var big := UI.label(tr, str(tier), 40, UI.GOLD, UI.TITLE_FONT, true)
	big.autowrap_mode = TextServer.AUTOWRAP_OFF
	var tv := VBoxContainer.new()
	UI.grow(tv)
	tr.add_child(tv)
	UI.label(tv, "TIER %d of %d" % [tier, Eco.PASS_TIERS], 14, UI.TEXT)
	if tier < Eco.PASS_TIERS:
		UI.progress(tv, int(d.pass.xp) - tier * Eco.TIER_XP, Eco.TIER_XP, UI.GOLD, 12)
		UI.label(tv, "%d / %d XP to tier %d" % [int(d.pass.xp) - tier * Eco.TIER_XP, Eco.TIER_XP, tier + 1], 11, UI.MUTED)
	if bool(d.pass.premium):
		var pr := UI.row(head, 8)
		UI.icon(pr, "crown", 22, UI.PURPLE)
		UI.label(pr, "PREMIUM ACTIVE — every premium reward unlocked", 13, UI.PURPLE)
	else:
		var b := UI.button(head, "UNLOCK PREMIUM  ·  %d GEMS" % Eco.PREMIUM_COST, "premium", func():
			app.confirm("UNLOCK PREMIUM?", "5 exclusive cosmetics, more gold and gems on every tier this season. Costs %d gems." % Eco.PREMIUM_COST, "UNLOCK", "premium", func():
				var r: Dictionary = p.buy_premium()
				if r.ok:
					app.sfx("purchase")
					app.toast("Premium pass unlocked!", UI.PURPLE)
				else:
					app.sfx("error")
					app.toast(str(r.error), UI.RED)
				app.rebuild()), "buy_premium", 15)
		b.disabled = int(d.gems) < Eco.PREMIUM_COST
		UI.label(head, "You have %d gems. Earn gems from the pass, weekly challenges and every 5 levels." % int(d.gems), 11, UI.MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var claimable := 0
	for t in range(1, tier + 1):
		for prem in [false, true]:
			if p.can_claim(t, prem):
				claimable += 1
	if claimable > 0:
		UI.button(root, "CLAIM ALL (%d)" % claimable, "claim", func():
			var got: Array = p.claim_all()
			app.sfx("coin")
			app.toast("Claimed %d reward%s" % [got.size(), "" if got.size() == 1 else "s"], UI.GREEN)
			app.rebuild(), "claim_all", 16)
	var legend := UI.row(root, 8)
	UI.grow(UI.label(legend, "FREE", 12, UI.MUTED)).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.grow(UI.label(legend, "PREMIUM", 12, UI.PURPLE)).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for t in range(1, Eco.PASS_TIERS + 1):
		var row := UI.row(root, 6)
		var badge := PanelContainer.new()
		var bs := StyleBoxFlat.new()
		bs.bg_color = UI.GOLD if t <= tier else Color(1, 1, 1, 0.08)
		bs.set_corner_radius_all(14)
		badge.add_theme_stylebox_override("panel", bs)
		badge.custom_minimum_size = Vector2(34, 34)
		row.add_child(badge)
		var bl := UI.label(badge, str(t), 14, Color("#2e1d00") if t <= tier else UI.MUTED, UI.HEAVY_FONT)
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		for prem in [false, true]:
			tier_cell(app, row, sid, t, prem)

static func tier_cell(app, parent: Node, sid: int, t: int, prem: bool) -> void:
	var p = app.profile
	var r: Dictionary = Eco.pass_reward(sid, t, prem)
	var rt: Array = reward_text(r)
	var cell := PanelContainer.new()
	var edge: Color = UI.PURPLE if prem else UI.CARD_HI
	var fill := Color(0.14, 0.09, 0.22, 0.92) if prem else UI.CARD
	if r.has("item"):
		edge = rt[2]
	var sb := UI.card_style(fill, 12, edge, false)
	sb.content_margin_left = 8
	sb.content_margin_right = 6
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	cell.add_theme_stylebox_override("panel", sb)
	UI.grow(cell)
	parent.add_child(cell)
	var row := UI.row(cell, 6)
	if str(rt[3]) != "":
		UI.tex_icon(row, str(rt[3]), 42)
	else:
		UI.icon(row, str(rt[0]), 24, rt[2])
	var l := UI.label(row, str(rt[1]), 11, UI.TEXT)
	UI.grow(l)
	var claimed: bool = (p.d.pass.prem if prem else p.d.pass.free).has(t)
	if claimed:
		UI.icon(row, "check", 18, UI.GREEN)
	elif p.can_claim(t, prem):
		UI.button(row, "GET", "claim", func():
			var res: Dictionary = p.claim_tier(t, prem)
			if res.ok:
				app.sfx("coin")
				var got: Array = reward_text(res.reward)
				app.toast("+ " + str(got[1]), UI.GREEN)
			app.rebuild(), "claim_%s_%d" % ["prem" if prem else "free", t], 11, 10)
	elif t > p.pass_tier() or (prem and not bool(p.d.pass.premium)):
		UI.icon(row, "lock", 16, UI.MUTED)

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
	show.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(show)
	show.show_look(cls, p.look_for(cls))
	var nm := UI.title(root, str(Eco.CLASS_NAMES[cls]).to_upper(), 20, UI.TEXT)
	for slot in ["skin", "weapon"]:
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
	for pair in [["master", "Master volume"], ["sfx", "Effects"]]:
		var key: String = pair[0]
		UI.label(au, str(pair[1]), 12, UI.MUTED)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = float(d.settings.get(key, 0.8))
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
