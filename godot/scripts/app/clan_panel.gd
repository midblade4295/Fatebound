extends Control
# 0.31.134 (Kevin): the CLAN window, beside FRIENDS (the tabs at the top switch between them).
# Not in a clan: invites waiting, FIND A CLAN (a search, the three houses as filters, JOIN / ASK on each), START A CLAN
# (name, tag, house -- never changes --, who may join, the lowest level; 10,000 gold, taken by the server).
# In a clan: its banner (house colours), CLAN CHAT, requests waiting (officers), INVITE A PLAYER by friend code
# (officers), the members (the leader's crown, OFFICER, each one's MANAGE for those you may manage), the settings
# (officers) and LEAVE / DISBAND. Everything goes through scripts/meta/social.gd; the server (server/clans.gd) decides.
# 0.31.148 (Kevin: "Make it cost 5000 gold and make a default clan for each faction that the new players can choose since
# there are no clans in game yet"): YOUR HOUSE'S CLAN first when not in a clan -- the three house clans (free, open to
# all; nobody runs them), JOIN on each; FIND A CLAN lists the players' clans under it. In a house clan: its banner,
# chat, members (the ones online first), and the players' clans to move to or START A CLAN (moving needs no leaving).
const UI = preload("res://scripts/app/ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")
const SocialUI = preload("res://scripts/app/social_ui.gd")

const JOIN_TEXT := {"open": "Open to all", "request": "Join by request", "invite": "Invite only"}

var app
var social
var _list: VBoxContainer
var _scroll: ScrollContainer
var _dirty := false
var _making := false                  # START CLAN sent, waiting for the server's answer
var _house := ""                      # the house picked for a new clan
var _join := "open"
var _min_lv := 1
var _fhouse := ""                     # FIND A CLAN's house filter ("" = all)
var _set_join := ""                   # the settings being edited (officers)
var _set_lv := 0
var _fields := {}                     # name -> LineEdit (what's typed survives a redraw)
var _typed := {}
var focus := ""                       # 0.31.147: "join" -- opened to join one
var _start_box: Control = null        # START A CLAN's section (START MY OWN CLAN scrolls to it)
var _shown_clan := ""                 # the clan the window was drawn for (a change: back to the top)
var _asked_list := false              # (0.31.148: in a house clan, the players' clans asked for once)

func open(a, f := "") -> void:
	app = a
	social = a.social
	focus = f
	var w := SocialUI.window(self, "CLAN", "castle", func():
		app.sfx("menuClose")
		app.close_modal(), 56.0 + float(app.safe_top), 24.0)
	var body: VBoxContainer = w.body
	SocialUI.social_tabs(body, app, "clan")
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.scroll_deadzone = 1000000
	body.add_child(_scroll)
	set_meta("drag_scroll", _scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	social.changed.connect(_on_changed)
	social.clan_made.connect(_on_made)
	if social.online() and not social.in_clan():
		social.clan_find("", "")
	_shown_clan = str(social.clan.get("id", ""))
	_render()

func _exit_tree() -> void:
	if social != null:
		if social.changed.is_connected(_on_changed):
			social.changed.disconnect(_on_changed)
		if social.clan_made.is_connected(_on_made):
			social.clan_made.disconnect(_on_made)

func _on_changed(what: String) -> void:
	if what in ["clan", "clans", "state", "me", "friends"]:
		_dirty = true

func _on_made(ok: bool, _why: String) -> void:
	_making = false
	if ok:
		app.sfx("confirm")
		for k in ["new_name", "new_tag"]:
			_typed.erase(k)
		app.clan_founded()
	_dirty = true

func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		var keep := _scroll.scroll_vertical
		var now_in := str(social.clan.get("id", ""))
		if now_in != _shown_clan:
			keep = 0                               # (joined, left or moved clans: the window from its top)
			_shown_clan = now_in
		for k in _fields:
			if is_instance_valid(_fields[k]):
				_typed[k] = (_fields[k] as LineEdit).text
		_render()
		_scroll.set_deferred("scroll_vertical", keep)

# ---------------- pieces ----------------
func _section(title: String, sub := "", rim := "") -> VBoxContainer:
	var f := UI2.frame(_list, "glass", 10, 16.0) if rim == "" else UI2.frame(_list, "night", 12, 18.0, rim)
	f.add_theme_constant_override("separation", 6)
	if title != "":
		var h := UI.row(f, 8)
		UI.grow(UI2.text(h, title, 17, UI2.GOLD))
		if sub != "":
			var s := UI.label(h, sub, 12, UI2.MUTED, UI.HEAVY_FONT)
			s.autowrap_mode = TextServer.AUTOWRAP_OFF
			s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return f

func _small(parent: Node, text: String, color: String, key: String, cb: Callable, w := 78.0) -> Button:
	var b := UI2.button(parent, text, color, cb, key, 13, 36.0, 11.0)
	b.custom_minimum_size.x = w
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b

func _field(parent: Node, key: String, placeholder: String, max_len: int) -> LineEdit:
	var e := SocialUI.field(parent, placeholder, max_len)
	e.text = str(_typed.get(key, ""))
	_fields[key] = e
	return e

func _fail() -> void:
	app.sfx("error")
	app.toast("Not connected to the server right now", UI.RED)

func _armed(b: Button, again: String, cb: Callable) -> void:
	# a button that needs a second tap (leave, disband, remove, hand over)
	b.pressed.connect(func():
		if b.has_meta("armed"):
			cb.call()
		else:
			b.set_meta("armed", true)
			b.text = again
			app.sfx("tap"))

func _clan_line(parent: Node, c: Dictionary) -> HBoxContainer:
	# a clan in a list: its house chip, [TAG] name, and house · members · who may join
	var r := UI.row(parent, 8)
	SocialUI.house_chip(r, str(c.get("house", "")))
	var nb := Button.new()
	nb.flat = true
	nb.focus_mode = Control.FOCUS_NONE
	nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nb.clip_text = true
	nb.custom_minimum_size = Vector2(0, 46)
	for st_name in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		nb.add_theme_stylebox_override(st_name, StyleBoxEmpty.new())
	nb.set_meta("action_key", "clan_card_" + str(c.get("id", "")))
	var cc := c.duplicate()
	nb.pressed.connect(func(): SocialUI.clan_card(app, self, cc))
	r.add_child(nb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nb.add_child(v)
	var top := UI.row(v, 6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tl := UI2.text(top, "[%s]" % str(c.get("tag", "")), 15, SocialUI.house_color(str(c.get("house", ""))))
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nl := UI2.text(top, str(c.get("name", "")), 15, Color.WHITE)
	nl.clip_text = true
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bits := ["%s" % SocialUI.house_name(str(c.get("house", ""))), "%d/%d" % [int(c.get("n", 0)), int(c.get("max", 30))],
		str(JOIN_TEXT.get(str(c.get("join", "")), ""))]
	if bool(c.get("hc", false)):
		bits = ["House clan", "%d member%s" % [int(c.get("n", 0)), "" if int(c.get("n", 0)) == 1 else "s"], "free, open to all"]
	if int(c.get("min_lv", 1)) > 1:
		bits.append("Lv %d+" % int(c.min_lv))
	var sl := UI.label(v, "  ·  ".join(bits), 11, UI2.MUTED, UI.HEAVY_FONT)
	sl.autowrap_mode = TextServer.AUTOWRAP_OFF
	sl.clip_text = true
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

# ---------------- the window ----------------
func _render() -> void:
	_fields = {}
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	if not social.online():
		var f := _section("NOT CONNECTED")
		var why := "Clans need the game's server. Trying again shortly..."
		if not social.has_account():
			why = "Clans start once you've been online with the game's server."
		elif str(social.state) == "connecting":
			why = "Connecting..."
		UI2.body(f, why, 13, UI2.SOFT)
		return
	if not social.has_clans:
		UI2.body(_section("CLANS"), "Clans arrive with the next server update.", 13, UI2.SOFT)
		return
	if social.in_clan():
		_render_mine()
	else:
		_render_free()

# ---------------- not in a clan ----------------
func _render_free() -> void:
	var cool: int = social.clan_cool_left()
	var intro := _section("JOIN A CLAN" if focus == "join" else "YOUR CLAN")
	if cool > 0:
		UI2.body(intro, "You left a clan recently. You can join a players' clan or start one again in %s -- your house's clan is open to you now." % _hours(cool), 13, UI2.GOLD)
	elif focus == "join":
		UI2.body(intro, "Pick your house's clan -- free, open to all -- or a players' clan. Or start your own and choose the house.", 13, UI2.SOFT)
	else:
		UI2.body(intro, "You're not in a clan yet. Join your house's clan or a players' clan below, or start your own. Every clan fights for one of the three houses.", 13, UI2.SOFT)
	# 0.31.147 (Kevin: "When they click join clan it put the list of available clans or they have option to start clan"):
	# the list is right under this; START MY OWN CLAN goes down to the form
	UI2.button(intro, "START MY OWN CLAN", "gold", func():
		app.sfx("tab")
		_to_start(), "clan_to_start", 14, 38.0)
	# ---- invites
	if not social.clan_inv.is_empty():
		var inf := _section("CLAN INVITES", str(social.clan_inv.size()))
		for c in social.clan_inv:
			_clan_line(inf, c)
			var by := UI.label(inf, "Invited by %s" % str(c.get("by", "")), 11, UI2.SOFT, UI.HEAVY_FONT)
			by.autowrap_mode = TextServer.AUTOWRAP_OFF
			var br := UI.row(inf, 8)
			var cid := str(c.get("id", ""))
			var jb := UI2.button(br, "JOIN", "green", func():
				app.sfx("confirm")
				if not social.clan_join(cid):
					_fail(), "clan_inv_join_" + cid, 15, 40.0)
			UI.grow(jb)
			UI2.dim_button(jb, cool > 0)
			var nb := _small(br, "NO THANKS", "ghost", "clan_inv_no_" + cid, func():
				app.sfx("tap")
				social.clan_noinv(cid), 120.0)
			nb.custom_minimum_size.y = 40
	# ---- 0.31.148: the house clans
	_house_section()
	_find_section(cool)
	# ---- start one
	_render_new(cool)

func _house_section() -> void:
	# 0.31.148: the three house clans, each with JOIN (free, open to all; the 24-hour wait doesn't apply)
	if social.house_clans.is_empty():
		return
	var hf := _section("YOUR HOUSE'S CLAN", "FREE")
	UI2.body(hf, "Every house has its own clan, open to all.", 12, UI2.MUTED)
	for c in social.house_clans:
		var r := _clan_line(hf, c)
		var cid := str(c.get("id", ""))
		if str(social.clan.get("id", "")) == cid:
			var y := UI.label(r, "YOURS", 12, UI2.GOLD, UI.HEAVY_FONT)
			y.autowrap_mode = TextServer.AUTOWRAP_OFF
			y.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			continue
		_small(r, "JOIN", "green", "clan_house_join_" + str(c.get("house", "")), func():
			app.sfx("confirm")
			if not social.clan_join(cid):
				_fail(), 76.0)

func _find_section(cool: int) -> void:
	var ff := _section("FIND A CLAN" if not social.in_house_clan() else "MOVE TO A PLAYERS' CLAN")
	var sr := UI.row(ff, 8)
	var q := _field(sr, "find", "Clan name or tag", 20)
	q.text_submitted.connect(func(_t): _search())
	_small(sr, "FIND", "blue", "clan_find", func(): _search(), 80.0)
	var hr := UI.row(ff, 6)
	for h in [""] + SocialUI.HOUSES:
		var hid: String = h
		var hb := UI2.button(hr, "ALL" if hid == "" else SocialUI.house_name(hid).to_upper(), "gold" if _fhouse == hid else "grey", func():
			app.sfx("tab")
			_fhouse = hid
			_search(), "clan_fhouse_" + (hid if hid != "" else "all"), 12, 32.0, 10.0)
		UI.grow(hb)
	var list: Array = social.clan_list.filter(func(c): return not bool(c.get("hc", false)))   # (the house clans: above)
	if list.is_empty():
		UI2.body(ff, "No players' clans yet -- be the first to start one!" if social.clan_query == "" and _fhouse == "" else "No clans match that.", 13, UI2.MUTED)
	for c in list:
		var r := _clan_line(ff, c)
		var cid := str(c.get("id", ""))
		var full: bool = int(c.get("n", 0)) >= int(c.get("max", 30))
		var invited: bool = social.clan_inv.any(func(x): return str(x.get("id", "")) == cid)
		var asked: bool = social.clan_asked.has(cid) or bool(c.get("asked", false))
		if full and not invited:
			UI2.dim_button(_small(r, "FULL", "grey", "clan_full_" + cid, func(): pass, 76.0), true)
		elif asked:
			_small(r, "ASKED", "ghost", "clan_asked_" + cid, func():
				app.sfx("tap")
				social.clan_unreq(cid)
				app.toast("Request taken back", UI.MUTED), 76.0)
		elif invited or str(c.get("join", "")) == "open":
			var b := _small(r, "JOIN", "green", "clan_join_" + cid, func():
				app.sfx("confirm")
				if not social.clan_join(cid):
					_fail(), 76.0)
			UI2.dim_button(b, cool > 0)
		elif str(c.get("join", "")) == "request":
			var b2 := _small(r, "ASK", "orange", "clan_ask_" + cid, func():
				app.sfx("confirm")
				if not social.clan_join(cid):
					_fail(), 76.0)
			UI2.dim_button(b2, cool > 0)
		else:
			UI2.dim_button(_small(r, "INVITE", "grey", "clan_inviteonly_" + cid, func():
				app.toast("This clan is invite only", UI.MUTED), 76.0), true)

func _search() -> void:
	var t := ""
	if _fields.has("find") and is_instance_valid(_fields["find"]):
		t = (_fields["find"] as LineEdit).text
	if not social.clan_find(t, _fhouse):
		_fail()

func _to_start() -> void:
	# scroll the window down to START A CLAN
	if is_instance_valid(_start_box):
		var pc := _start_box.get_parent() as Control
		_scroll.scroll_vertical = int(pc.position.y) if pc != null else int(_start_box.position.y)

func _render_new(cool: int) -> void:
	var nf := _section("START A CLAN")
	_start_box = nf
	var gold := int(app.profile.d.get("gold", 0))
	var cost: int = social.clan_cost
	UI2.body(nf, "Costs %s gold (you have %s). Your clan's house can never change." % [_thousands(cost), _thousands(gold)], 13,
		UI2.SOFT if gold >= cost else Color("#ffb0a0"))
	var nr := UI.row(nf, 8)
	var ne := _field(nr, "new_name", "Clan name", 20)
	ne.size_flags_stretch_ratio = 3.0
	var te := _field(nr, "new_tag", "TAG", 4)
	te.size_flags_stretch_ratio = 1.2
	te.text_changed.connect(func(tx: String):           # (a tag is capitals: shown so as it's typed)
		if tx != tx.to_upper():
			var at := te.caret_column
			te.text = tx.to_upper()
			te.caret_column = at)
	UI2.body(nf, "HOUSE", 12, UI2.MUTED)
	var hr := UI.row(nf, 8)
	for h in SocialUI.HOUSES:
		var hid: String = h
		var picked := _house == hid
		var hb := UI2.button(hr, SocialUI.house_name(hid).to_upper(), SocialUI.house_button(hid) if picked else "grey", func():
			app.sfx("tab")
			_house = hid
			_dirty = true, "clan_house_" + hid, 15, 42.0, 12.0)
		UI.grow(hb)
		if not picked and _house != "":
			hb.modulate = Color(1, 1, 1, 0.6)
	UI2.body(nf, "WHO MAY JOIN", 12, UI2.MUTED)
	var jr := UI.row(nf, 6)
	for j in ["open", "request", "invite"]:
		var jid: String = j
		var jb := UI2.button(jr, {"open":"OPEN", "request":"REQUEST", "invite":"INVITE"}[jid], "gold" if _join == jid else "grey", func():
			app.sfx("tab")
			_join = jid
			_dirty = true, "clan_join_mode_" + jid, 13, 36.0, 10.0)
		UI.grow(jb)
	_level_row(nf, "LOWEST LEVEL", _min_lv, func(v: int):
		_min_lv = v
		_dirty = true, "clan_new_lv")
	var go := UI2.button(nf, "WAITING..." if _making else "START CLAN  ·  %s GOLD" % _thousands(cost), "gold", func(): _start(), "clan_start", 17, 48.0)
	UI2.dim_button(go, _making or cool > 0 or gold < cost)

func _level_row(parent: Node, title: String, value: int, set_cb: Callable, key: String) -> void:
	var r := UI.row(parent, 8)
	var l := UI.label(r, title, 12, UI2.MUTED, UI.HEAVY_FONT)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(sp)
	_small(r, "−", "blue", key + "_down", func():
		app.sfx("tap")
		set_cb.call(maxi(1, value - (5 if value > 10 else 1))), 44.0)
	var v := UI2.text(r, "Lv %d" % value, 16, Color.WHITE)
	v.custom_minimum_size.x = 64
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_small(r, "+", "blue", key + "_up", func():
		app.sfx("tap")
		set_cb.call(mini(100, value + (5 if value >= 10 else 1))), 44.0)

func _start() -> void:
	if _making:
		return
	var name := ""
	var tag := ""
	if is_instance_valid(_fields.get("new_name")):
		name = (_fields["new_name"] as LineEdit).text.strip_edges()
	if is_instance_valid(_fields.get("new_tag")):
		tag = (_fields["new_tag"] as LineEdit).text.strip_edges().to_upper()
	var why := ""
	if name.length() < 3:
		why = "Give your clan a name (3-20 letters)"
	elif tag.length() < 3 or not _alnum(tag):
		why = "A tag is 3-4 letters or numbers (like WOLF)"
	elif _house == "":
		why = "Pick your clan's house"
	elif social.clan_cool_left() > 0:
		why = "You can start a clan again in %s" % _hours(social.clan_cool_left())
	elif int(app.profile.d.get("gold", 0)) < int(social.clan_cost):
		why = "Starting a clan costs %s gold" % _thousands(int(social.clan_cost))
	if why != "":
		app.sfx("error")
		app.toast(why, UI.RED)
		return
	if not social.clan_new(name, tag, _house, _join, _min_lv):
		_fail()
		return
	app.sfx("tap")
	_making = true
	_dirty = true

static func _alnum(t: String) -> bool:
	for ch in t:
		if not ((ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9")):
			return false
	return true

# ---------------- in a clan ----------------
func _render_mine() -> void:
	var c: Dictionary = social.clan
	var house := str(c.get("house", ""))
	var role: String = social.clan_role_of_me()
	var officer: bool = social.is_clan_officer()
	# ---- the banner
	var bf := _section("", "", SocialUI.house_rim(house))
	var tr := UI.row(bf, 10)
	var ic := UI2.icon(tr, "banner", 54.0)
	ic.modulate = SocialUI.house_color(house).lightened(0.15)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", -2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr.add_child(tv)
	var nl := UI2.text(tv, str(c.get("name", "")), 22, Color.WHITE)
	nl.clip_text = true
	var hl := UI2.text(tv, "[%s]  ·  HOUSE %s" % [str(c.get("tag", "")), SocialUI.house_name(house).to_upper()], 14, SocialUI.house_color(house))
	hl.clip_text = true
	var hc := bool(c.get("hc", false))
	var bits := ["%d / %d members" % [int(c.get("n", 0)), int(c.get("max", 30))], str(JOIN_TEXT.get(str(c.get("join", "")), ""))]
	if hc:
		bits = ["The %s' own clan" % SocialUI.house_name(house), "%d member%s" % [int(c.get("n", 0)), "" if int(c.get("n", 0)) == 1 else "s"]]
	if int(c.get("min_lv", 1)) > 1:
		bits.append("Lv %d+" % int(c.min_lv))
	var il := UI.label(bf, "  ·  ".join(bits), 12, UI2.SOFT, UI.HEAVY_FONT)
	il.autowrap_mode = TextServer.AUTOWRAP_OFF
	var cr := UI.row(bf, 8)
	var n := int(social.unread.get("clan", 0))
	UI.grow(UI2.button(cr, "CLAN CHAT" + ("  (%d)" % n if n > 0 else ""), "orange", func():
		app.sfx("menuOpen")
		app.open_chat("clan"), "clan_chat", 16, 44.0))
	var you := UI.label(cr,{"leader":"YOU LEAD", "officer":"OFFICER", "member":"MEMBER"}.get(role, ""), 12, UI2.GOLD, UI.HEAVY_FONT)
	you.autowrap_mode = TextServer.AUTOWRAP_OFF
	you.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# ---- requests (officers)
	var req: Array = c.get("req", [])
	if officer and not req.is_empty():
		var rf := _section("REQUESTS", str(req.size()))
		for p in req:
			var r := _member_row(rf, p, "")
			var lv := UI.label(r, "Lv %d" % int(p.get("lv", 1)), 12, UI2.GOLD, UI.HEAVY_FONT)
			lv.autowrap_mode = TextServer.AUTOWRAP_OFF
			lv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var pp := str(p.pid)
			_small(r, "ACCEPT", "green", "clan_accept_" + pp, func():
				app.sfx("confirm")
				if not social.clan_accept(pp):
					_fail(), 84.0)
			_small(r, "✕", "ghost", "clan_reject_" + pp, func():
				app.sfx("tap")
				social.clan_reject(pp), 44.0)
	# ---- invite (officers)
	if officer:
		var vf := _section("INVITE A PLAYER")
		var vr := UI.row(vf, 8)
		var ve := _field(vr, "invite", "Their friend code", 12)
		ve.text_submitted.connect(func(_t): _invite_code())
		_small(vr, "INVITE", "green", "clan_invite_code", func(): _invite_code(), 90.0)
		UI2.body(vf, "Or tap a player's name anywhere (chat, friends, ranks) and choose INVITE TO CLAN.", 12, UI2.MUTED)
	# ---- members
	var shown: int = (c.get("members", []) as Array).size()
	var mf := _section("MEMBERS", ("%d / %d" % [int(c.get("n", 0)), int(c.get("max", 30))]) if not hc
		else ("%d" % int(c.get("n", 0)) if shown >= int(c.get("n", 0)) else "%d SHOWN OF %d" % [shown, int(c.get("n", 0))]))
	for m in c.get("members", []):
		var mrole := str(m.get("role", "member"))
		var r := _member_row(mf, m, mrole)
		var mp := str(m.pid)
		if mp == str(social.me.get("pid", "")):
			var y := UI.label(r, "YOU", 12, UI2.GOLD, UI.HEAVY_FONT)
			y.autowrap_mode = TextServer.AUTOWRAP_OFF
			y.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		elif role == "leader" or (role == "officer" and mrole == "member"):
			var mc: Dictionary = m.duplicate()
			_small(r, "MANAGE", "blue", "clan_manage_" + mp, func(): _manage(mc), 92.0)
	# ---- settings (officers)
	if officer:
		var sf := _section("SETTINGS")
		if _set_join == "":
			_set_join = str(c.get("join", "open"))
			_set_lv = int(c.get("min_lv", 1))
		UI2.body(sf, "WHO MAY JOIN", 12, UI2.MUTED)
		var jr := UI.row(sf, 6)
		for j in ["open", "request", "invite"]:
			var jid: String = j
			UI.grow(UI2.button(jr, {"open":"OPEN", "request":"REQUEST", "invite":"INVITE"}[jid], "gold" if _set_join == jid else "grey", func():
				app.sfx("tab")
				_set_join = jid
				_dirty = true, "clan_set_join_" + jid, 13, 36.0, 10.0))
		_level_row(sf, "LOWEST LEVEL", _set_lv, func(v: int):
			_set_lv = v
			_dirty = true, "clan_set_lv")
		var changed: bool = _set_join != str(c.get("join", "")) or _set_lv != int(c.get("min_lv", 1))
		var sb := UI2.button(sf, "SAVE SETTINGS", "green", func():
			if social.clan_set(_set_join, _set_lv):
				app.sfx("confirm")
				_set_join = ""
			else:
				_fail(), "clan_set_save", 15, 42.0)
		UI2.dim_button(sb, not changed)
	if hc:
		# 0.31.148: a house clan -- the players' clans to move to, or start one (no leaving first, no wait)
		var nf := _section("A CLAN OF YOUR OWN?")
		UI2.body(nf, "Join a players' clan or start your own any time: you move over from %s by itself." % str(c.get("name", "")), 12, UI2.MUTED)
		UI2.button(nf, "START MY OWN CLAN", "gold", func():
			app.sfx("tab")
			_to_start(), "clan_to_start", 14, 38.0)
		if not _asked_list:
			_asked_list = true
			social.clan_find("", "")
		_find_section(social.clan_cool_left())
		_render_new(social.clan_cool_left())
	# ---- leave / disband
	var lf := _section("")
	var lr := UI.row(lf, 8)
	var lb := UI2.button(lr, "LEAVE CLAN", "red", func(): pass, "clan_leave", 15, 42.0)
	UI.grow(lb)
	_armed(lb, "TAP AGAIN TO LEAVE", func():
		app.sfx("menuClose")
		if not social.clan_leave():
			_fail())
	if role == "leader":
		var db := UI2.button(lr, "DISBAND", "grey", func(): pass, "clan_disband", 15, 42.0)
		UI.grow(db)
		_armed(db, "SURE? ENDS IT FOR ALL", func():
			app.sfx("menuClose")
			if not social.clan_disband():
				_fail())
	var note := "Leaving means waiting 24 hours before joining another clan."
	if hc:
		note = "Leaving your house's clan has no wait."
	if role == "leader":
		note += " If you leave, an officer takes over."
	UI2.body(lf, note, 12, UI2.MUTED)

func _member_row(parent: Node, m: Dictionary, role: String) -> HBoxContainer:
	var r := UI.row(parent, 8)
	SocialUI.dot(r, str(m.get("st", "offline")))
	var nb := Button.new()
	nb.flat = true
	nb.focus_mode = Control.FOCUS_NONE
	nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nb.clip_text = true
	nb.custom_minimum_size = Vector2(0, 44)
	for st_name in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		nb.add_theme_stylebox_override(st_name, StyleBoxEmpty.new())
	nb.set_meta("action_key", "clan_member_" + str(m.get("pid", "")))
	var card := m.duplicate()
	nb.pressed.connect(func(): SocialUI.name_card(app, self, card))
	r.add_child(nb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nb.add_child(v)
	var top := UI.row(v, 6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if role == "leader":
		UI2.icon(top, "crown", 18.0).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UI2.text(top, str(m.get("n", "Player")), 15, Color.WHITE)
	if role == "officer":
		var ol := UI.label(top, "OFFICER", 11, UI2.CYAN, UI.HEAVY_FONT)
		ol.autowrap_mode = TextServer.AUTOWRAP_OFF
		ol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	else:
		SocialUI.title_label(top, str(m.get("tt", "")), 11)
	if m.has("st"):
		var sl := UI.label(v, SocialUI.status_text(m), 11, SocialUI.ST_COL.get(str(m.get("st", "offline")), UI2.MUTED).lightened(0.25), UI.HEAVY_FONT)
		sl.autowrap_mode = TextServer.AUTOWRAP_OFF
		sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _invite_code() -> void:
	if not is_instance_valid(_fields.get("invite")):
		return
	var t := (_fields["invite"] as LineEdit).text.strip_edges().replace("#", "").replace(" ", "").to_lower()
	if t.length() != 10 or not t.is_valid_hex_number():
		app.sfx("error")
		app.toast("A friend code is 10 letters and numbers (like 3FA21C9B0D)", UI.RED)
		return
	if social.clan_invite(t):
		app.sfx("confirm")
		_typed.erase("invite")
		(_fields["invite"] as LineEdit).text = ""
	else:
		_fail()

func _manage(m: Dictionary) -> void:
	# what the leader (or an officer, for members) can do with one member
	app.sfx("menuOpen")
	var ov := Control.new()
	ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(ov)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent):
		if (ev is InputEventMouseButton or ev is InputEventScreenTouch) and not ev.pressed:
			ov.queue_free())
	ov.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(cc)
	var v := UI2.frame(cc, "royal", 14, 20.0, "gold")
	(v.get_parent() as Control).custom_minimum_size = Vector2(minf(320.0, size.x - 40.0), 0)
	var pid := str(m.get("pid", ""))
	var role := str(m.get("role", "member"))
	var mine: String = social.clan_role_of_me()
	UI2.center(UI2.text(v, str(m.get("n", "Player")), 22, Color.WHITE))
	UI2.center(UI2.body(v, {"officer":"Officer", "member":"Member"}.get(role, ""), 13, UI2.MUTED))
	var done := func(ok: bool) -> void:
		if not ok:
			_fail()
		if is_instance_valid(ov):
			ov.queue_free()
	if mine == "leader":
		if role == "member":
			UI2.button(v, "MAKE OFFICER", "blue", func():
				app.sfx("confirm")
				done.call(social.clan_role(pid, "officer")), "clan_m_officer", 15, 42.0)
		else:
			UI2.button(v, "MAKE MEMBER", "blue", func():
				app.sfx("tap")
				done.call(social.clan_role(pid, "member")), "clan_m_member", 15, 42.0)
		var lb := UI2.button(v, "MAKE LEADER", "gold", func(): pass, "clan_m_lead", 15, 42.0)
		_armed(lb, "SURE? THEY LEAD", func():
			app.sfx("confirm")
			done.call(social.clan_lead(pid)))
	var kb := UI2.button(v, "REMOVE FROM CLAN", "red", func(): pass, "clan_m_kick", 15, 42.0)
	_armed(kb, "TAP AGAIN TO REMOVE", func():
		app.sfx("menuClose")
		done.call(social.clan_kick(pid)))
	UI2.button(v, "CLOSE", "ghost", func():
		app.sfx("menuClose")
		ov.queue_free(), "clan_m_close", 14, 36.0)

# ---------------- text ----------------
static func _hours(secs: int) -> String:
	var h := int(ceil(secs / 3600.0))
	return "%d hour%s" % [h, "" if h == 1 else "s"]

static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out
