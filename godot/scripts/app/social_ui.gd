extends RefCounted
# 0.31.111 (Kevin: "Build a global chat and players can click a name and have option to add friend to a friends list.
# They can then group up and form a party"): the pieces the chat and friends screens share -- the window frame, a
# player's status dot and line, and the card that opens when a name is tapped (add friend / invite / remove / block /
# report). The connection and the state are in scripts/meta/social.gd.
const UI = preload("res://scripts/app/ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const CREST = preload("res://scripts/app/crest.gd")

const ST_COL := {"online": Color("#5fdc86"), "match": Color("#ffb13d"), "offline": Color("#6b778a")}
const RARITY_COL := {"common": Color("#cfd8e0"), "rare": Color("#6cc4ff"), "epic": Color("#d6a2ff"), "legendary": Color("#ffc23d")}
const NAME_ME := Color("#8cf0a8")              # 0.31.196: green, as everywhere your name is (0.31.195: no yellow text)
const NAME_OTHER := Color("#9fd8ff")
const REPORTS := [["language", "Offensive language"], ["spam", "Spam"], ["cheating", "Cheating"], ["name", "Offensive name"], ["other", "Something else"]]
# 0.31.134: the three houses a clan belongs to
const HOUSES := ["lions", "stags", "ravens"]
const HOUSE_NAME := {"lions": "Lions", "stags": "Stags", "ravens": "Ravens"}
const HOUSE_COL := {"lions": Color("#ffc23d"), "stags": Color("#6be07c"), "ravens": Color("#c99bff")}
const HOUSE_RIM := {"lions": "orange", "stags": "green", "ravens": "purple"}
const HOUSE_BTN := {"lions": "gold", "stags": "green", "ravens": "purple"}

static func house_name(h: String) -> String:
	return str(HOUSE_NAME.get(h, "?"))

static func house_color(h: String) -> Color:
	return HOUSE_COL.get(h, UI2.MUTED)

static func house_rim(h: String) -> String:
	return str(HOUSE_RIM.get(h, "gold"))

static func house_button(h: String) -> String:
	return str(HOUSE_BTN.get(h, "grey"))

static func house_chip(parent: Node, h: String, px := 14.0) -> Panel:
	# a small round chip in the house's colour
	var d := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = house_color(h)
	sb.border_color = house_color(h).darkened(0.55)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(px))
	d.add_theme_stylebox_override("panel", sb)
	d.custom_minimum_size = Vector2(px, px)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(d)
	return d

static func crest(parent: Node, code: String, h := 20.0, frame := "") -> Control:
	# 0.31.196: a clan's crest ("e.f.c"), h px tall (scripts/app/crest.gd); an empty one for no crest
	var c = CREST.new()
	c.set_crest(code, frame)
	c.custom_minimum_size = Vector2(roundf(h / CREST.ASPECT), h) if code != "" else Vector2.ZERO
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.visible = code != ""
	parent.add_child(c)
	return c

static func social_tabs(parent: Node, app, on: String) -> void:
	# FRIENDS | CLAN at the top of both windows (a badge count on the other one)
	var tr := UI.row(parent, 8)
	var social = app.social
	for t in [["friends", "FRIENDS"], ["clan", "CLAN"]]:
		var id: String = t[0]
		var n := 0
		if social != null and social.online():
			n = (social.rin.size() + social.invites.size()) if id == "friends" else (social.clan_inv.size() + (social.clan_requests() if social.is_clan_officer() else 0))
		var b := UI2.button(tr, str(t[1]) + ("  (%d)" % n if n > 0 and id != on else ""), "gold" if id == on else "blue", func():
			if id != on:
				app.sfx("tab")
				app.open_social(id), "social_tab_" + id, 15, 38.0, 12.0)
		UI.grow(b)

static func ago(secs: int) -> String:
	if secs < 90:
		return "just now"
	if secs < 3600:
		return "%dm ago" % (secs / 60)
	if secs < 86400:
		return "%dh ago" % (secs / 3600)
	return "%dd ago" % (secs / 86400)

static func status_text(c: Dictionary) -> String:
	match str(c.get("st", "offline")):
		"online": return "Online"
		"match": return "In the lobby" if int(c.get("jn", 0)) == 1 else "In a match"   # 0.31.209: (a lobby can be joined)
	var seen := int(c.get("seen", 0))
	return "Last seen " + ago(int(Time.get_unix_time_from_system()) - seen) if seen > 0 else "Offline"

static func dot(parent: Node, st: String, px := 10.0) -> Panel:
	var d := Panel.new()
	var s := StyleBoxFlat.new()
	s.bg_color = ST_COL.get(st, ST_COL.offline)
	s.set_corner_radius_all(int(px))
	if st != "offline":
		s.shadow_color = Color(s.bg_color, 0.6)
		s.shadow_size = 3
	d.add_theme_stylebox_override("panel", s)
	d.custom_minimum_size = Vector2(px, px)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(d)
	return d

static func title_label(parent: Node, tt: String, size := 11) -> Label:
	var t: Array = Net.TITLES.get(tt, [])
	if t.is_empty():
		return null
	var l := UI.label(parent, str(t[0]), size, RARITY_COL.get(str(t[2]), RARITY_COL.common), UI.HEAVY_FONT)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l

static func field(parent: Node, placeholder: String, max_len: int) -> LineEdit:
	# a text field in the game's look: dark, gold-edged, round
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.max_length = max_len
	e.custom_minimum_size = Vector2(0, 46)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.add_theme_font_override("font", UI.HEAVY_FONT)
	e.add_theme_font_size_override("font_size", 16)
	e.add_theme_color_override("font_color", Color.WHITE)
	e.add_theme_color_override("font_placeholder_color", Color(0.75, 0.8, 0.92, 0.55))
	e.add_theme_color_override("caret_color", UI2.GOLD)
	e.add_theme_color_override("selection_color", Color(1.0, 0.84, 0.35, 0.35))
	for st_name in ["normal", "focus", "read_only"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.02, 0.04, 0.1, 0.92)
		s.border_color = Color("#f7cd55") if st_name == "focus" else Color("#8a6a2a")
		s.set_border_width_all(2)
		s.set_corner_radius_all(14)
		s.content_margin_left = 14
		s.content_margin_right = 14
		s.content_margin_top = 6
		s.content_margin_bottom = 6
		e.add_theme_stylebox_override(st_name, s)
	parent.add_child(e)
	return e

static func window(panel: Control, title: String, icon: String, on_close: Callable, top := 56.0, bottom := 24.0) -> Dictionary:
	# the frame both screens open in: a dimmed backdrop and a gold-rimmed sheet with a title row and a close button.
	# -> {"margin", "body" (the sheet's VBox), "head" (the title row)}
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.06, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	margin.add_theme_constant_override("margin_top", int(top))
	margin.add_theme_constant_override("margin_bottom", int(bottom))
	panel.add_child(margin)
	var body := UI2.frame(margin, "night", 12, 20.0, "gold")
	body.add_theme_constant_override("separation", 8)
	var head := UI.row(body, 8)
	var ic := UI2.icon(head, icon, 38.0)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tl := UI2.text(head, title, 26, UI2.GOLD)
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var x := UI2.button(head, "✕", "ghost", on_close, "social_close", 18, 40.0, 12.0)
	x.custom_minimum_size.x = 44
	x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return {"margin": margin, "body": body, "head": head}

# ---------------- the card behind a name ----------------
static func name_card(app, host: Control, c: Dictionary) -> void:
	var social = app.social
	var pid := str(c.get("pid", ""))
	if social == null or pid == "" or social.relation(pid) == "me":
		return
	app.sfx("menuOpen")
	for o in host.get_children():
		if o.has_meta("name_card"):
			o.queue_free()
	var ov := Control.new()
	ov.set_meta("name_card", true)
	ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(ov)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent):
		if (ev is InputEventMouseButton or ev is InputEventScreenTouch) and not ev.pressed:
			app.sfx("menuClose")
			ov.queue_free())
	ov.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(cc)
	var v := UI2.frame(cc, "royal", 14, 20.0, "gold")
	(v.get_parent() as Control).custom_minimum_size = Vector2(minf(330.0, host.size.x - 40.0), 0)
	v.add_theme_constant_override("separation", 8)
	_fill_card(app, ov, v, c)
	# 0.31.120 (Kevin: player profile card): its numbers come from the server; the card fills in when they arrive
	social.ask_profile(pid)
	var on_ch := func(what: String) -> void:
		if what == "prof" and is_instance_valid(ov) and is_instance_valid(v) and not v.has_meta("reporting") and ov.is_inside_tree():
			_fill_card(app, ov, v, c)
	social.changed.connect(on_ch)
	ov.tree_exiting.connect(func():
		if social.changed.is_connected(on_ch):
			social.changed.disconnect(on_ch))

static func _close(app, ov: Control) -> void:
	if is_instance_valid(ov):
		ov.queue_free()

static func _fill_card(app, ov: Control, v: VBoxContainer, c0: Dictionary) -> void:
	for ch in v.get_children():
		ch.queue_free()
	var social = app.social
	var pid := str(c0.get("pid", ""))
	var c: Dictionary = social.card_of(pid)
	if c.is_empty():
		c = c0
	var rel: String = social.relation(pid)
	var pr0: Dictionary = social.profile_of(pid)
	var ct := str(c.get("ct", pr0.get("ct", "")))      # 0.31.134: their clan's tag
	var nl := UI2.text(v, str(c.get("n", "Player")), 24, Color.WHITE)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if ct != "":
		var crow := HBoxContainer.new()                  # 0.31.196: the crest beside the tag
		crow.alignment = BoxContainer.ALIGNMENT_CENTER
		crow.add_theme_constant_override("separation", 6)
		v.add_child(crow)
		crest(crow, str(c.get("cc", pr0.get("cc", ""))), 22.0)
		UI2.text(crow, "[%s]" % ct, 15, UI2.GOLD)
	var tr := HBoxContainer.new()
	tr.alignment = BoxContainer.ALIGNMENT_CENTER
	tr.add_theme_constant_override("separation", 8)
	v.add_child(tr)
	title_label(tr, str(c.get("tt", "")), 13)
	var code := UI.label(tr, "#" + pid.to_upper(), 12, UI2.MUTED, UI.HEAVY_FONT)
	code.autowrap_mode = TextServer.AUTOWRAP_OFF
	if c.has("st") and rel == "friend":
		var sr := HBoxContainer.new()
		sr.alignment = BoxContainer.ALIGNMENT_CENTER
		sr.add_theme_constant_override("separation", 6)
		v.add_child(sr)
		dot(sr, str(c.st))
		UI.label(sr, status_text(c), 12, UI2.SOFT, UI.HEAVY_FONT).autowrap_mode = TextServer.AUTOWRAP_OFF
	_stats_block(v, social.profile_of(pid), social.online())
	var act := func(ok: bool) -> void:
		if not ok:
			app.sfx("error")
			app.toast("Not connected to the server right now", UI.RED)
		else:
			_close(app, ov)
	match rel:
		"none":
			UI2.button(v, "ADD FRIEND", "green", func():
				app.sfx("confirm")
				act.call(social.add(pid)), "card_add", 17, 46.0)
		"sent":
			var sb := UI2.button(v, "FRIEND REQUEST SENT", "grey", func(): pass, "card_sent", 15, 42.0)
			UI2.dim_button(sb, true)
			UI2.button(v, "TAKE IT BACK", "ghost", func():
				app.sfx("tap")
				act.call(social.unfriend(pid)), "card_unsend", 14, 38.0)
		"asked":
			var r := UI.row(v, 8)
			UI.grow(UI2.button(r, "ACCEPT", "green", func():
				app.sfx("confirm")
				act.call(social.add(pid)), "card_accept", 17, 46.0))
			UI.grow(UI2.button(r, "DECLINE", "ghost", func():
				app.sfx("tap")
				act.call(social.decline(pid)), "card_decline", 15, 46.0))
		"friend":
			var st := str(c.get("st", "offline"))
			var full: bool = social.in_party() and social.party_size() + (social.party.get("pending", []) as Array).size() >= social.clan_party_max()
			var can: bool = st == "online" and not social.in_my_party(pid) and not full
			var why := "INVITE TO PARTY"
			if social.in_my_party(pid):
				why = "IN YOUR PARTY"
			elif st == "match":
				why = "IN A MATCH"
			elif st == "offline":
				why = "OFFLINE"
			elif full:
				why = "PARTY FULL"
			if social.can_join(c) and not social.in_my_party(pid) and app.has_method("join_friend"):   # 0.31.209: its countdown only
				# 0.31.120 (Kevin: "make so it's a join match option")
				UI2.button(v, "JOIN THEIR MATCH", "green", func():
					_close(app, ov)
					app.join_friend(pid), "card_join", 17, 46.0)
			else:
				var ib := UI2.button(v, why, "orange" if can else "grey", func():
					if can:
						app.sfx("confirm")
						act.call(social.invite(pid)), "card_invite", 17, 46.0)
				UI2.dim_button(ib, not can)
			var rb := UI2.button(v, "REMOVE FRIEND", "ghost", func(): pass, "card_remove", 14, 38.0)
			rb.pressed.connect(func():
				if rb.has_meta("armed"):
					app.sfx("menuClose")
					act.call(social.unfriend(pid))
				else:
					rb.set_meta("armed", true)
					rb.text = "TAP AGAIN TO REMOVE"
					app.sfx("tap"))
		"blocked":
			UI2.button(v, "UNBLOCK", "blue", func():
				app.sfx("tap")
				act.call(social.unblock(pid)), "card_unblock", 16, 44.0)
	if rel in ["none", "sent", "asked"] and social.has_lfg and social.in_my_clan(pid):
		# 0.31.196: a clanmate who isn't a friend can be invited to the party too
		var cst := str(c.get("st", "offline"))
		var cfull: bool = social.in_party() and social.party_size() + (social.party.get("pending", []) as Array).size() >= social.clan_party_max()
		var ccan: bool = cst == "online" and not social.in_my_party(pid) and not cfull
		var cwhy := "INVITE TO PARTY"
		if social.in_my_party(pid):
			cwhy = "IN YOUR PARTY"
		elif cst == "match":
			cwhy = "IN A MATCH"
		elif cst == "offline":
			cwhy = "OFFLINE"
		elif cfull:
			cwhy = "PARTY FULL"
		var cib := UI2.button(v, cwhy, "orange" if ccan else "grey", func():
			if ccan:
				app.sfx("confirm")
				act.call(social.invite(pid)), "card_invite", 17, 46.0)
		UI2.dim_button(cib, not ccan)
	if rel != "blocked" and social.has_clans and social.is_clan_officer() and ct == "" and not social.in_my_clan(pid):
		# 0.31.134: officers invite players who aren't in a clan
		UI2.button(v, "INVITE TO CLAN", "purple", func():
			app.sfx("confirm")
			act.call(social.clan_invite(pid)), "card_clan_invite", 15, 42.0)
	var r2 := UI.row(v, 8)
	if rel != "blocked":
		var bb := UI2.button(r2, "BLOCK", "red", func(): pass, "card_block", 14, 40.0)
		UI.grow(bb)
		bb.pressed.connect(func():
			if bb.has_meta("armed"):
				app.sfx("menuClose")
				act.call(social.block(pid))
			else:
				bb.set_meta("armed", true)
				bb.text = "SURE? TAP AGAIN"
				app.sfx("tap"))
	UI.grow(UI2.button(r2, "REPORT", "grey", func():
		app.sfx("tap")
		_report_menu(app, ov, v, c), "card_report", 14, 40.0))
	UI2.button(v, "CLOSE", "ghost", func():
		app.sfx("menuClose")
		_close(app, ov), "card_close", 14, 36.0)

static func _report_menu(app, ov: Control, v: VBoxContainer, c: Dictionary) -> void:
	for ch in v.get_children():
		ch.queue_free()
	v.set_meta("reporting", true)
	var pid := str(c.get("pid", ""))
	UI2.center(UI2.text(v, "REPORT %s" % str(c.get("n", "Player")).to_upper(), 20, Color.WHITE))
	UI2.center(UI2.body(v, "What's wrong? The report goes to the developer with their last messages.", 12, UI2.SOFT))
	for r in REPORTS:
		var key: String = r[0]
		UI2.button(v, str(r[1]).to_upper(), "blue", func():
			if app.social.report(pid, key):
				app.sfx("confirm")
				_close(app, ov)
			else:
				app.sfx("error")
				app.toast("Not connected to the server right now", UI.RED), "report_" + key, 15, 40.0)
	UI2.button(v, "BACK", "ghost", func():
		app.sfx("menuClose")
		_fill_card(app, ov, v, c), "report_back", 14, 36.0)

# ---------------- the profile card's numbers (0.31.120) ----------------
static func since_text(t: int) -> String:
	if t <= 0:
		return ""
	var dt := Time.get_datetime_dict_from_unix_time(t)
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%s %d" % [months[clampi(int(dt.month) - 1, 0, 11)], int(dt.year)]

static func _tile(g: GridContainer, n: String, cap: String, col := Color.WHITE) -> void:
	var t := VBoxContainer.new()
	t.add_theme_constant_override("separation", -3)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.add_child(t)
	var nl := UI2.text(t, n, 19, col)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var cl := Label.new()
	cl.text = cap
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cl.add_theme_font_override("font", UI.HEAVY_FONT)
	cl.add_theme_font_size_override("font_size", 10)
	cl.add_theme_color_override("font_color", UI2.MUTED)
	cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_child(cl)

static func _stats_block(v: VBoxContainer, pr: Dictionary, online: bool) -> void:
	var f := UI2.frame(v, "glass", 10, 14.0)
	f.add_theme_constant_override("separation", 8)
	f.set_meta("action_key", "card_stats")
	if pr.is_empty() or not bool(pr.get("ok", false)):
		var why := "Loading..." if online and pr.is_empty() else "No profile to show"
		if str(pr.get("why", "")) == "busy":
			why = "Too many at once -- try again in a moment"
		var l := UI2.body(f, why, 12, UI2.MUTED)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size.y = 120
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		return
	# the class they play most, and the outfit they wear on him (0.31.188: it was the weapon they won most with)
	var cls := str(pr.get("cls", ""))
	var outfit := str(pr.get("sk", ""))
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	f.add_child(top)
	var portrait := ("res://assets/ui/skins/%s.png" % outfit) if outfit != "" and Eco.SKINS.has(outfit) else "res://assets/ui/skins/default_%s.png" % cls
	var tex: Texture2D = UI2.tex(portrait) if cls != "" and ResourceLoader.exists(portrait) else null
	if tex != null:
		var disc := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#20314a")
		sb.set_corner_radius_all(30)
		sb.set_border_width_all(2)
		sb.border_color = UI2.GOLD
		disc.add_theme_stylebox_override("panel", sb)
		disc.custom_minimum_size = Vector2(60, 60)
		disc.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(disc)
		var t := TextureRect.new()
		t.texture = tex
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		disc.add_child(t)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(tv)
	if cls != "":
		UI2.text(tv, str(Eco.CLASS_NAMES.get(cls, cls.capitalize())), 18, UI2.GOLD)
		var cm := int(pr.get("cm", 0))
		var sub := UI.label(tv, "Plays most  ·  %d match%s, %d won" % [cm, "" if cm == 1 else "es", int(pr.get("cw", 0))], 11, UI2.SOFT, UI.HEAVY_FONT)
		sub.autowrap_mode = TextServer.AUTOWRAP_OFF
	else:
		UI2.text(tv, "New recruit", 18, UI2.GOLD)
	if outfit != "" and Eco.SKINS.has(outfit):
		var wl := UI.label(tv, "Wears " + str(Eco.SKINS[outfit].name), 12, Color(str(Eco.RARITY_COLOR.get(str(Eco.SKINS[outfit].rarity), "#ffffff"))), UI.HEAVY_FONT)
		wl.autowrap_mode = TextServer.AUTOWRAP_OFF
		wl.clip_text = true
	# the numbers
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 6)
	f.add_child(g)
	var m := int(pr.get("m", 0))
	_tile(g, str(int(pr.get("lv", 1))), "LEVEL", UI2.GOLD)
	_tile(g, str(int(pr.get("w", 0))), "WINS")
	_tile(g, ("%d%%" % roundi(100.0 * int(pr.get("w", 0)) / m)) if m > 0 else "-", "WIN RATE")
	_tile(g, str(int(pr.get("tw", 0))), "TOWERS")                 # (0.31.169: was Siege's RESCUES)
	_tile(g, str(int(pr.get("ko", 0))), "KNOCKOUTS")
	_tile(g, str(int(pr.get("bs", 0))), "BEST STREAK")
	var bits := []
	if int(pr.get("rank", 0)) > 0:
		bits.append("#%d this week" % int(pr.rank))
	bits.append("%d matches" % m)
	if since_text(int(pr.get("since", 0))) != "":
		bits.append("since " + since_text(int(pr.since)))
	var foot := UI.label(f, "  ·  ".join(bits), 11, UI2.MUTED, UI.HEAVY_FONT)
	foot.autowrap_mode = TextServer.AUTOWRAP_OFF
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

# ---------------- a clan's card (0.31.134) ----------------
static func clan_card(app, host: Control, c0: Dictionary) -> void:
	var social = app.social
	var id := str(c0.get("id", ""))
	if social == null or id == "":
		return
	app.sfx("menuOpen")
	for o in host.get_children():
		if o.has_meta("clan_card"):
			o.queue_free()
	var ov := Control.new()
	ov.set_meta("clan_card", true)
	ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(ov)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent):
		if (ev is InputEventMouseButton or ev is InputEventScreenTouch) and not ev.pressed:
			app.sfx("menuClose")
			ov.queue_free())
	ov.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(cc)
	var v := UI2.frame(cc, "night", 14, 20.0, "gold")
	(v.get_parent() as Control).custom_minimum_size = Vector2(minf(340.0, host.size.x - 32.0), 0)
	v.add_theme_constant_override("separation", 8)
	_fill_clan_card(app, ov, v, c0)
	social.clan_info(id)
	var on_ch := func(what: String) -> void:
		if what in ["clan_info", "clan"] and is_instance_valid(ov) and is_instance_valid(v) and ov.is_inside_tree():
			_fill_clan_card(app, ov, v, c0)
	social.changed.connect(on_ch)
	ov.tree_exiting.connect(func():
		if social.changed.is_connected(on_ch):
			social.changed.disconnect(on_ch))

static func _fill_clan_card(app, ov: Control, v: VBoxContainer, c0: Dictionary) -> void:
	for ch in v.get_children():
		ch.queue_free()
	var social = app.social
	var id := str(c0.get("id", ""))
	var info: Dictionary = social.clan_infos.get(id, {})
	var c: Dictionary = c0.duplicate()
	c.merge(info, true)
	var house := str(c.get("house", ""))
	if str(c.get("cc", "")) != "":
		# 0.31.196: its crest (in its League frame), [TAG] and level
		var cw := CenterContainer.new()
		v.add_child(cw)
		crest(cw, str(c.cc), 64.0, str(c.get("fr", "")))
	var nl := UI2.text(v, str(c.get("name", "")), 22, Color.WHITE)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub_line := "[%s]  ·  HOUSE %s" % [str(c.get("tag", "")), house_name(house).to_upper()]
	if int(c.get("cv", 0)) >= 2:
		sub_line = "[%s]  ·  %s" % [str(c.get("tag", "")), "STARTER CLAN" if bool(c.get("hc", false)) else "LEVEL %d" % int(c.get("lv", 1))]
	var hl := UI2.text(v, sub_line, 14, UI2.SOFT if int(c.get("cv", 0)) >= 2 else house_color(house))
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bits := ["%d / %d members" % [int(c.get("n", 0)), int(c.get("max", 30))],
		{"open":"Open to all", "request":"Join by request", "invite":"Invite only"}.get(str(c.get("join", "")), "")]
	if int(c.get("min_lv", 1)) > 1:
		bits.append("Lv %d+" % int(c.min_lv))
	var bl := UI.label(v, "  ·  ".join(bits), 12, UI2.SOFT, UI.HEAVY_FONT)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.autowrap_mode = TextServer.AUTOWRAP_OFF
	var f := UI2.frame(v, "glass", 10, 14.0)
	f.add_theme_constant_override("separation", 4)
	var members: Array = info.get("members", [])
	if info.is_empty():
		UI2.body(f, "Loading..." if social.online() else "Not connected", 12, UI2.MUTED)
	elif members.is_empty():
		UI2.body(f, "That clan is gone", 12, UI2.MUTED)
	for m in members.slice(0, 12):
		var r := UI.row(f, 6)
		if str(m.get("role", "")) == "leader":
			UI2.icon(r, "crown", 16.0).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var ml := UI2.text(r, str(m.get("n", "Player")), 14, Color.WHITE)
		ml.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ml.clip_text = true
		if str(m.get("role", "")) == "officer":
			var ol := UI.label(r, "OFFICER", 10, UI2.CYAN, UI.HEAVY_FONT)
			ol.autowrap_mode = TextServer.AUTOWRAP_OFF
			ol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if members.size() > 12:
		UI2.body(f, "and %d more" % (members.size() - 12), 12, UI2.MUTED)
	var done := func(ok: bool) -> void:
		if not ok:
			app.sfx("error")
			app.toast("Not connected to the server right now", UI.RED)
		elif is_instance_valid(ov):
			ov.queue_free()
	if not social.in_clan():
		var invited: bool = social.clan_inv.any(func(x): return str(x.get("id", "")) == id) or bool(c.get("invited", false))
		var asked: bool = social.clan_asked.has(id) or bool(c.get("asked", false))
		var full := int(c.get("n", 0)) >= int(c.get("max", 30))
		var cool: bool = social.clan_cool_left() > 0
		if asked:
			UI2.button(v, "TAKE BACK MY REQUEST", "ghost", func():
				app.sfx("tap")
				done.call(social.clan_unreq(id)), "clan_card_unreq", 14, 40.0)
		elif full and not invited:
			UI2.dim_button(UI2.button(v, "FULL", "grey", func(): pass, "clan_card_full", 15, 44.0), true)
		elif invited or str(c.get("join", "")) == "open":
			var jb := UI2.button(v, "JOIN", "green", func():
				app.sfx("confirm")
				done.call(social.clan_join(id)), "clan_card_join", 17, 46.0)
			UI2.dim_button(jb, cool)
		elif str(c.get("join", "")) == "request":
			var ab := UI2.button(v, "ASK TO JOIN", "orange", func():
				app.sfx("confirm")
				done.call(social.clan_join(id)), "clan_card_ask", 17, 46.0)
			UI2.dim_button(ab, cool)
		else:
			UI2.dim_button(UI2.button(v, "INVITE ONLY", "grey", func(): pass, "clan_card_inviteonly", 15, 44.0), true)
	UI2.button(v, "CLOSE", "ghost", func():
		app.sfx("menuClose")
		if is_instance_valid(ov):
			ov.queue_free(), "clan_card_close", 14, 36.0)
