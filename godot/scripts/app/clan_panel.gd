extends Control
# 0.31.134 (Kevin): the CLAN window, beside FRIENDS (the tabs at the top switch between them).
# Not in a clan: invites waiting, FIND A CLAN (a search, JOIN / ASK on each), START A CLAN (name, tag, who may join, the
# lowest level; 5,000 gold, taken by the server). In a clan: CLAN CHAT, requests waiting (officers), INVITE A PLAYER by
# friend code (officers), the members (the leader's crown, OFFICER, each one's MANAGE for those you may manage), the
# settings (officers) and LEAVE / DISBAND. Everything goes through scripts/meta/social.gd; the server (server/clans.gd)
# decides.
# 0.31.148 (Kevin: "make a default clan for each faction that the new players can choose"): the three house clans (free,
# open to all; nobody runs them) first when not in a clan, JOIN on each; in one, the players' clans to move to or START A
# CLAN (moving needs no leaving).
# 0.31.196 (Kevin: "Now let's redo the clan system for new game" -> "Do clan chest, clan camp, crest, shard requests,
# 5 - stack, lfg button, league"): no houses -- a clan has a CREST (picked when it's made; the leader and officers change
# it: CHANGE CREST), the house clans are the STARTER CLANS. In a clan the window opens on its CAMP (scripts/app/
# clan_camp.gd: the camp at its level's stage, its banners in the crest's colours) with the clan's crest, name, level and
# XP over it, and three tabs:
#   CAMP     CLAN CHAT; the CLAN CHEST (the week's points against its four tiers, mine, last week's result); PLAY
#            TOGETHER (LOOKING FOR GROUP: a call in clan chat clanmates JOIN; the calls open; a party of 5); SHARD
#            REQUESTS (ASK FOR A SHARD of a hero you don't own; GIVE a clanmate one you hold, for its melt gold); then
#            requests, invite, crest and settings (officers), and LEAVE / DISBAND
#   MEMBERS  each member's points this week
#   LEAGUE   this week's clans by points (clan_league), the prizes, last week's podium
# Against a server older than 0.31.196 (no "cv"): the clan as before, with a line that the rest comes with its update.
# 0.31.197 (Kevin: "make the camp screen fill the entire screen instead of being a small box and incorporate the clan
# buttons into the screen"): in a clan the window IS the camp -- the painting fills the screen (clan_camp.gd) and the
# clan's buttons stand in it: at the top FRIENDS and close, the crest with the clan's name, level and XP in the sky, any
# clanmate's LFG call (JOIN) under them; on the ground by the fire the CLAN CHEST (its tier, the week's points) and the
# SHARD REQUESTS board; then CHAT, MEMBERS, LEAGUE and CLAN (crest, settings, leave); and LOOKING FOR GROUP at the
# bottom. Each but CHAT and LFG opens its sheet over the camp (the CHEST, SHARDS, MEMBERS, LEAGUE, CLAN parts of 0.31.196).
const UI = preload("res://scripts/app/ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")
const SocialUI = preload("res://scripts/app/social_ui.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const ClanCamp = preload("res://scripts/app/clan_camp.gd")
const Crest = preload("res://scripts/app/crest.gd")
const Screens = preload("res://scripts/app/screens.gd")

const JOIN_TEXT := {"open": "Open to all", "request": "Join by request", "invite": "Invite only"}
const TIER_COL := {"wooden": Color("#c08a55"), "silver": Color("#c9d3dc"), "gold": Color("#ffcf4a"), "royal": Color("#c47bff")}
const FRAME_COL := {"gold": Color("#ffcf4a"), "silver": Color("#d6e0ea"), "bronze": Color("#e0955a")}
const LEAGUE_STALE := 20.0             # s before LEAGUE asks the server again

var app
var social
var _list: VBoxContainer
var _scroll: ScrollContainer
var _dirty := false
var _making := false                  # START CLAN sent, waiting for the server's answer
var _crest := {}                      # the crest for a new clan {"e", "f", "c"}
var _join := "open"
var _min_lv := 1
var _set_join := ""                   # the settings being edited (officers)
var _set_lv := 0
var _fields := {}                     # name -> LineEdit (what's typed survives a redraw)
var _typed := {}
var focus := ""                       # 0.31.147: "join" -- opened to join one
var _start_box: Control = null        # START A CLAN's section (START MY OWN CLAN scrolls to it)
var _shown_clan := ""                 # the clan the window was drawn for (a change: back to the top)
var _asked_list := false              # (0.31.148: in a house clan, the players' clans asked for once)
var mode := ""                        # 0.31.197: "window" (not in a clan, an older server) or "full" (the camp)
var camp: Control = null              # the camp painting on screen (clan_camp.gd)
var _camp_key := ""                   # (redrawn only when its stage, crest or frame changes)
var sheet := ""                       # 0.31.197: the sheet open over the camp ("chest", "shards", "members", "league", "clan")
var _camp_layer: Control = null
var _ui_layer: Control = null
var _sheet_layer: Control = null
var _overlay: Control = null          # the crest editor or the hero picker, over the window
var _league_asked := -999.0

func open(a, f := "") -> void:
	app = a
	social = a.social
	focus = f
	_crest = random_crest()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	social.changed.connect(_on_changed)
	social.clan_made.connect(_on_made)
	if social.online() and not social.in_clan():
		social.clan_find("", "")
	_shown_clan = str(social.clan.get("id", ""))
	_render()

func _want_mode() -> String:
	return "full" if social.online() and social.has_clans and social.in_clan() and social.clan_v2() else "window"

func _build(m: String) -> void:
	# the window (a framed list) or the camp (full screen, its layers) -- everything that was here goes
	mode = m
	for c in get_children():
		if c != _overlay:
			remove_child(c)
			c.queue_free()
	camp = null
	_camp_key = ""
	sheet = ""
	_list = null
	_scroll = null
	if m == "window":
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
	else:
		var bg := ColorRect.new()
		bg.color = Color(0.02, 0.02, 0.06)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(bg)
		for n in ["CampLayer", "UiLayer", "SheetLayer"]:
			var l := Control.new()
			l.name = n
			l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(l)
		_camp_layer = get_node("CampLayer")
		_ui_layer = get_node("UiLayer")
		_sheet_layer = get_node("SheetLayer")
		if has_meta("drag_scroll"):
			remove_meta("drag_scroll")
	if is_instance_valid(_overlay):
		move_child(_overlay, get_child_count() - 1)

func _exit_tree() -> void:
	if social != null:
		if social.changed.is_connected(_on_changed):
			social.changed.disconnect(_on_changed)
		if social.clan_made.is_connected(_on_made):
			social.clan_made.disconnect(_on_made)

func _on_changed(what: String) -> void:
	if what in ["clan", "clans", "state", "me", "friends", "league", "party"]:
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
		var keep := _scroll.scroll_vertical if is_instance_valid(_scroll) else 0
		var now_in := str(social.clan.get("id", ""))
		if now_in != _shown_clan:
			keep = 0                               # (joined, left or moved clans: the window from its top)
			_shown_clan = now_in
			sheet = ""
		for k in _fields:
			if is_instance_valid(_fields[k]):
				_typed[k] = (_fields[k] as LineEdit).text
		_render()
		if is_instance_valid(_scroll):
			_scroll.set_deferred("scroll_vertical", keep)

static func random_crest() -> Dictionary:
	var e := randi() % Eco.CLAN_EMBLEMS.size()
	var f := randi() % 6                         # (the strong colours first: blue, red, green, purple, orange, night)
	var c := 0 if f != 9 else 2
	if randf() < 0.35:
		c = 1                                    # gold
	return {"e":e, "f":f, "c":c}

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

func _note_label(parent: Node, s: String, size := 12, col := UI2.MUTED) -> Label:
	var l := UI.label(parent, s, size, col, UI.HEAVY_FONT)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _clan_line(parent: Node, c: Dictionary) -> HBoxContainer:
	# a clan in a list: its crest (0.31.196; a house chip from an older server), [TAG] name, and level · members · who
	# may join
	var r := UI.row(parent, 8)
	if str(c.get("cc", "")) != "":
		SocialUI.crest(r, str(c.cc), 34.0, str(c.get("fr", "")))
	else:
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
	var v2 := int(c.get("cv", 0)) >= 2
	var tl := UI2.text(top, "[%s]" % str(c.get("tag", "")), 15, UI2.SOFT if v2 else SocialUI.house_color(str(c.get("house", ""))))
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nl := UI2.text(top, str(c.get("name", "")), 15, Color.WHITE)
	nl.clip_text = true
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bits := ["Lv %d" % int(c.get("lv", 1)) if v2 else SocialUI.house_name(str(c.get("house", ""))), "%d/%d" % [int(c.get("n", 0)), int(c.get("max", 30))],
		str(JOIN_TEXT.get(str(c.get("join", "")), ""))]
	if bool(c.get("hc", false)):
		bits = ["Starter clan", "%d member%s" % [int(c.get("n", 0)), "" if int(c.get("n", 0)) == 1 else "s"], "free, open to all"]
	elif v2 and int(c.get("pts", 0)) > 0:
		bits.insert(1, "%s pts this week" % _thousands(int(c.pts)))
	if int(c.get("min_lv", 1)) > 1:
		bits.append("Lv %d+ to join" % int(c.min_lv))
	var sl := UI.label(v, "  ·  ".join(bits), 11, UI2.MUTED, UI.HEAVY_FONT)
	sl.autowrap_mode = TextServer.AUTOWRAP_OFF
	sl.clip_text = true
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

# ---------------- the window ----------------
func _render() -> void:
	_fields = {}
	var want := _want_mode()
	if want != mode:
		_build(want)
	if mode == "full":
		_render_full()
		return
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
		_render_mine_old()
	else:
		_render_free()

# ---------------- not in a clan ----------------
func _render_free() -> void:
	var cool: int = social.clan_cool_left()
	var intro := _section("JOIN A CLAN" if focus == "join" else "YOUR CLAN")
	if cool > 0:
		UI2.body(intro, "You left a clan recently. You can join a players' clan or start one again in %s -- the starter clans are open to you now." % _hours(cool), 13, UI2.CYAN)
	elif focus == "join":
		UI2.body(intro, "Pick a starter clan -- free, open to all -- or a players' clan. Or start your own with its own crest.", 13, UI2.SOFT)
	else:
		UI2.body(intro, "You're not in a clan yet. Clans fill a Clan Chest every week, climb the Clan League, party up 5 at a time and share hero shards. Join one below or start your own.", 13, UI2.SOFT)
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
	# ---- 0.31.148: the house clans (0.31.196: the starter clans)
	_house_section()
	_find_section(cool)
	# ---- start one
	_render_new(cool)

func _house_section() -> void:
	# 0.31.148: the three house clans, each with JOIN (free, open to all; the 24-hour wait doesn't apply)
	if social.house_clans.is_empty():
		return
	var hf := _section("STARTER CLANS", "FREE")
	UI2.body(hf, "Open to all, no wait to leave. Players' clans fill a Clan Chest and play in the League.", 12, UI2.MUTED)
	for c in social.house_clans:
		var r := _clan_line(hf, c)
		var cid := str(c.get("id", ""))
		if str(social.clan.get("id", "")) == cid:
			_note_label(r, "YOURS", 12, UI2.GREEN)
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
	var list: Array = social.clan_list.filter(func(c): return not bool(c.get("hc", false)))   # (the starter clans: above)
	if list.is_empty():
		UI2.body(ff, "No players' clans yet -- be the first to start one!" if social.clan_query == "" else "No clans match that.", 13, UI2.MUTED)
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
	if not social.clan_find(t, ""):
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
	UI2.body(nf, "Costs %s gold (you have %s)." % [_thousands(cost), _thousands(gold)], 13,
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
	UI2.body(nf, "CREST", 12, UI2.MUTED)
	crest_editor(nf, _crest, "crest", func(k: Dictionary):
		_crest = k
		_dirty = true)
	if not social.has_lfg:
		UI2.body(nf, "(Your crest shows once the game's server updates.)", 11, UI2.MUTED)
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
	_note_label(r, title)
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
	elif Eco.clean_crest(_crest).is_empty():
		why = "Pick your clan's crest"
	elif social.clan_cool_left() > 0:
		why = "You can start a clan again in %s" % _hours(social.clan_cool_left())
	elif int(app.profile.d.get("gold", 0)) < int(social.clan_cost):
		why = "Starting a clan costs %s gold" % _thousands(int(social.clan_cost))
	if why != "":
		app.sfx("error")
		app.toast(why, UI.RED)
		return
	if not social.clan_new(name, tag, Eco.clean_crest(_crest), _join, _min_lv):
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

# ---------------- the crest editor (0.31.196) ----------------
func crest_editor(parent: Node, k: Dictionary, key: String, changed: Callable) -> void:
	# the crest as it stands (big) with SHUFFLE; the sixteen emblems (each in the crest's colours), the shield's colours,
	# the emblem's colours. Every tap calls changed with the new {"e", "f", "c"}.
	var cur := Eco.clean_crest(k)
	if cur.is_empty():
		cur = {"e":0, "f":0, "c":0}
	var top := UI.row(parent, 12)
	var pv := SocialUI.crest(top, Eco.crest_code(cur), 92.0)
	pv.set_meta("crest_preview", Eco.crest_code(cur))
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(tv)
	UI2.body(tv, "Your clan's banner: on its camp, beside every member's name and on the League.", 12, UI2.SOFT)
	UI2.button(tv, "SHUFFLE", "blue", func():
		app.sfx("tap")
		changed.call(random_crest()), key + "_random", 13, 34.0, 10.0)
	_note_label(parent, "EMBLEM", 11)
	var g := GridContainer.new()
	g.columns = 8
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 4)
	parent.add_child(g)
	for i in Eco.CLAN_EMBLEMS.size():
		var ei: int = i
		var b := _swatch(g, Color(str(Eco.CLAN_FIELDS[int(cur.f)])), int(cur.e) == ei, key + "_e_%d" % ei, func():
			app.sfx("tab")
			changed.call({"e":ei, "f":int(cur.f), "c":int(cur.c)}))
		var t := TextureRect.new()
		t.texture = Crest.tex("emblem_" + str(Eco.CLAN_EMBLEMS[ei]))
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		t.modulate = Color(str(Eco.CLAN_CHARGES[int(cur.c)]))
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		t.offset_left = 5
		t.offset_top = 5
		t.offset_right = -5
		t.offset_bottom = -5
		b.add_child(t)
	_note_label(parent, "SHIELD", 11)
	var fr := GridContainer.new()
	fr.columns = 10
	fr.add_theme_constant_override("h_separation", 4)
	parent.add_child(fr)
	for i in Eco.CLAN_FIELDS.size():
		var fi: int = i
		_swatch(fr, Color(str(Eco.CLAN_FIELDS[fi])), int(cur.f) == fi, key + "_f_%d" % fi, func():
			app.sfx("tab")
			changed.call({"e":int(cur.e), "f":fi, "c":int(cur.c)}), 28.0)
	_note_label(parent, "EMBLEM COLOUR", 11)
	var cr := GridContainer.new()
	cr.columns = 8
	cr.add_theme_constant_override("h_separation", 4)
	parent.add_child(cr)
	for i in Eco.CLAN_CHARGES.size():
		var ci: int = i
		_swatch(cr, Color(str(Eco.CLAN_CHARGES[ci])), int(cur.c) == ci, key + "_c_%d" % ci, func():
			app.sfx("tab")
			changed.call({"e":int(cur.e), "f":int(cur.f), "c":ci}), 30.0)

func _swatch(parent: Node, fill: Color, on: bool, key: String, cb: Callable, h := 36.0) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for st_name in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = fill
		sb.set_corner_radius_all(8)
		sb.border_color = Color("#ffe08a") if on else Color(0, 0, 0, 0.55)
		sb.set_border_width_all(3 if on else 1)
		b.add_theme_stylebox_override(st_name, sb)
	b.set_meta("action_key", key)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _open_overlay(title: String, w := 340.0, quiet := false) -> VBoxContainer:
	_close_overlay()
	if not quiet:
		app.sfx("menuOpen")
	var ov := Control.new()
	ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(ov)
	_overlay = ov
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent):
		if (ev is InputEventMouseButton or ev is InputEventScreenTouch) and not ev.pressed:
			app.sfx("menuClose")
			_close_overlay())
	ov.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(cc)
	var v := UI2.frame(cc, "royal", 14, 20.0, "gold")
	(v.get_parent() as Control).custom_minimum_size = Vector2(minf(w, size.x - 28.0), 0)
	UI2.center(UI2.text(v, title, 20, Color.WHITE))
	return v

func _close_overlay() -> void:
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null

func _edit_crest(k: Dictionary, again := false) -> void:
	# CHANGE CREST (the leader and officers)
	var v := _open_overlay("CHANGE CREST", 360.0, again)
	crest_editor(v, k, "crest_edit", func(nk: Dictionary): _edit_crest(nk, true))
	var r := UI.row(v, 8)
	UI.grow(UI2.button(r, "CANCEL", "ghost", func():
		app.sfx("menuClose")
		_close_overlay(), "clan_crest_cancel", 14, 42.0))
	var same: bool = Eco.crest_code(k) == social.my_crest()
	var sb := UI2.button(r, "SAVE CREST", "green", func():
		if social.clan_crest(Eco.clean_crest(k)):
			app.sfx("confirm")
			_close_overlay()
		else:
			_fail(), "clan_crest_save", 15, 42.0)
	UI.grow(sb)
	UI2.dim_button(sb, same)

# ---------------- in a clan: the camp, full screen (0.31.196; 0.31.197) ----------------
func _render_full() -> void:
	var c: Dictionary = social.clan
	var hc := bool(c.get("hc", false))
	var lv := int(c.get("lv", 1))
	var key := "%d|%s|%s" % [Eco.clan_camp_stage(lv), str(c.get("cc", "")), str(c.get("fr", ""))]
	if key != _camp_key or not is_instance_valid(camp):
		_camp_key = key
		for ch in _camp_layer.get_children():
			ch.queue_free()
		camp = ClanCamp.new()
		camp.setup(Eco.clan_camp_stage(lv), str(c.get("cc", "")), str(c.get("fr", "")), bool(app.profile.d.settings.get("reduce_motion", false)))
		camp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_camp_layer.add_child(camp)
	for ch in _ui_layer.get_children():
		_ui_layer.remove_child(ch)
		ch.queue_free()
	var mc := MarginContainer.new()
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_theme_constant_override("margin_left", 12)
	mc.add_theme_constant_override("margin_right", 12)
	mc.add_theme_constant_override("margin_top", int(8.0 + float(app.safe_top)))
	mc.add_theme_constant_override("margin_bottom", 16)
	_ui_layer.add_child(mc)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_child(col)
	# ---- the top: FRIENDS, close
	var top := UI.row(col, 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fr_n: int = social.rin.size() + social.invites.size()
	var fb := UI2.button(top, "FRIENDS" + ("  (%d)" % fr_n if fr_n > 0 else ""), "blue", func():
		app.sfx("tab")
		app.open_social("friends"), "social_tab_friends", 14, 38.0, 12.0, UI2.icon_path("friends"))
	fb.custom_minimum_size.x = 126
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(sp)
	var xb := UI2.button(top, "✕", "ghost", func():
		app.sfx("menuClose")
		app.close_modal(), "clan_close", 18, 38.0, 12.0)
	xb.custom_minimum_size.x = 46
	# ---- the sky: the crest, the clan's name, level and XP
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 0)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	var cw := CenterContainer.new()
	cw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(cw)
	var big := SocialUI.crest(cw, str(c.get("cc", "")), 84.0, str(c.get("fr", "")))
	big.set_meta("clan_crest_big", true)
	var nl := UI2.text(head, str(c.get("name", "")), 26, Color.WHITE)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sub := "[%s]  ·  %s" % [str(c.get("tag", "")), "STARTER CLAN" if hc else "LEVEL %d" % lv]
	if str(c.get("fr", "")) != "":
		sub += "  ·  LEAGUE #%d" % ({"gold":1, "silver":2, "bronze":3}.get(str(c.fr), 0))
	var sl := UI2.text(head, sub, 14, FRAME_COL.get(str(c.get("fr", "")), UI2.CREAM))
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not hc:
		var xp := int(c.get("xp", 0))
		var at := Eco.clan_level_xp(lv)
		var nxt := Eco.clan_level_xp(lv + 1)
		var xc := CenterContainer.new()
		xc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(xc)
		var xr := UI.row(xc, 6)
		xr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		xr.custom_minimum_size.x = 250
		if nxt > 0:
			var b := UI2.bar(xr, float(xp - at), float(nxt - at), Color("#d9f99a"), Color("#5bbf3a"), 10.0)
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_note_label(xr, "%s / %s XP" % [_thousands(xp - at), _thousands(nxt - at)], 11, UI2.CREAM)
		else:
			_note_label(xr, "MAX LEVEL  ·  %s XP" % _thousands(xp), 11, UI2.GREEN)
	# ---- clanmates calling for players (JOIN)
	var me_pid := str(social.me.get("pid", ""))
	for call in c.get("lfg", []):
		var pid := str(call.get("pid", ""))
		if pid == me_pid or social.in_my_party(pid):
			continue
		var bc := CenterContainer.new()
		bc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(bc)
		var pill := UI2.frame(bc, "night", 6, 16.0, "green")
		var pr := UI.row(pill, 8)
		UI2.icon(pr, "horn", 26.0).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_note_label(pr, "%s wants players  %d/%d" % [str(call.get("n", "Player")), int(call.get("size", 1)), int(call.get("max", 5))], 13, Color.WHITE)
		_small(pr, "JOIN", "green", "clan_lfg_join_" + pid, func():
			app.sfx("confirm")
			if not social.lfg_join(pid):
				_fail(), 70.0)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)
	# ---- on the ground by the fire: the CLAN CHEST, the SHARD REQUESTS board
	var ground := UI.row(col, 8)
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if hc:
		_spot(ground, UI2.icon_path("castle"), "STARTER CLAN", "Players' clans fill a chest", -1.0, 0, "clan_open_starter", func(): _open_sheet("clan"))
	else:
		var pts := int(c.get("pts", 0))
		var tier := Eco.clan_tier(pts)
		var nxt_i := mini(tier, Eco.CLAN_CHEST_TIERS.size() - 1)
		var need := int(Eco.CLAN_CHEST_TIERS[nxt_i][0])
		var shown := Eco.clan_chest_of(maxi(1, tier))
		var line := "%s / %s pts" % [_thousands(pts), _thousands(need)] if tier < Eco.CLAN_CHEST_TIERS.size() else "%s pts  ·  ROYAL!" % _thousands(pts)
		var chest := _spot(ground, Screens.chest_icon(shown), "CLAN CHEST", line, float(pts) / float(need), 0, "clan_open_chest", func(): _open_sheet("chest"))
		chest.set_meta("clan_chest_tier", tier)
		if tier == 0:
			(chest.get_meta("icon") as Control).modulate = Color(0.62, 0.62, 0.7, 0.9)
	var gsp := Control.new()
	gsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gsp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ground.add_child(gsp)
	var others := (c.get("asks", []) as Array).filter(func(a): return str(a.get("pid", "")) != me_pid)
	var can_give := others.filter(func(a): return app.profile.giftable_shards(str(a.get("h", ""))) > 0).size()
	var mine_ask: Dictionary = social.my_ask()
	var sline := "You asked: %s" % _hero(str(mine_ask.h)) if not mine_ask.is_empty() else ("%d open" % others.size() if not others.is_empty() else "Ask your clan")
	_spot(ground, UI2.icon_path("scroll"), "SHARDS", sline, -1.0, can_give if can_give > 0 else 0, "clan_open_shards", func(): _open_sheet("shards"))
	# ---- CHAT, MEMBERS, LEAGUE, CLAN
	var med := UI.row(col, 6)
	med.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var unread := int(social.unread.get("clan", 0))
	_medallion(med, "chat", "CHAT", unread, "clan_chat", func():
		app.sfx("menuOpen")
		app.open_chat("clan", "clan"))
	var req_n: int = social.clan_requests() if social.is_clan_officer() else 0
	_medallion(med, "friends", "MEMBERS", req_n, "clan_open_members", func(): _open_sheet("members"),
		"%d/%d" % [int(c.get("n", 0)), int(c.get("max", 30))] if not hc else "%d" % int(c.get("n", 0)))
	var rank := 0
	var lg: Dictionary = social.league
	if not lg.is_empty() and not (lg.get("me", {}) as Dictionary).is_empty():
		rank = int(lg.me.get("rank", 0))
	_medallion(med, "trophy", "LEAGUE", 0, "clan_open_league", func(): _open_sheet("league"), "#%d this week" % rank if rank > 0 else "")
	_medallion(med, "gear", "CLAN", 0, "clan_open_clan", func(): _open_sheet("clan"))
	# ---- LOOKING FOR GROUP
	_lfg_plaque(col)
	if sheet != "":
		_open_sheet(sheet, true)

func _spot(parent: Node, icon_path: String, title: String, line: String, frac: float, badge: int, key: String, cb: Callable) -> Button:
	# a place on the camp's ground that opens something: its picture, a soft glow under it, its name and a line (and a
	# bar when frac >= 0)
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	for st_name in ["normal", "hover", "focus", "hover_pressed"]:
		b.add_theme_stylebox_override(st_name, StyleBoxEmpty.new())
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(1, 1, 1, 0.08)
	pressed.set_corner_radius_all(14)
	b.add_theme_stylebox_override("pressed", pressed)
	b.custom_minimum_size = Vector2(150, 128)
	b.set_meta("action_key", key)
	b.pressed.connect(func():
		app.sfx("menuOpen")
		cb.call())
	parent.add_child(b)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_END
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var ic_box := Control.new()
	ic_box.custom_minimum_size = Vector2(0, 64)
	ic_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ic_box)
	UI2.glow(ic_box, Rect2(30, 6, 90, 70), Color(1.0, 0.8, 0.45, 0.45))
	var ic := UI2.img(ic_box, icon_path, 64.0)
	ic.position = Vector2(43, 0)
	b.set_meta("icon", ic)
	if badge > 0:
		UI2.badge(ic, str(badge), Vector2(8, -4))
	var t := UI2.text(v, title, 15, Color.WHITE)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if frac >= 0.0:
		var bc := MarginContainer.new()
		bc.add_theme_constant_override("margin_left", 22)
		bc.add_theme_constant_override("margin_right", 22)
		bc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(bc)
		UI2.bar(bc, clampf(frac, 0.0, 1.0), 1.0, Color("#ffe9a6"), Color("#e09a2a"), 9.0)
	var l := UI.label(v, line, 11, UI2.CREAM, UI.HEAVY_FONT, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b

func _medallion(parent: Node, icon: String, title: String, badge: int, key: String, cb: Callable, sub := "") -> Button:
	# a round medallion standing in the camp: its icon on a plate (a badge for what waits), its name under it
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	for st_name in ["normal", "hover", "focus", "hover_pressed"]:
		b.add_theme_stylebox_override(st_name, StyleBoxEmpty.new())
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(1, 1, 1, 0.08)
	pressed.set_corner_radius_all(14)
	b.add_theme_stylebox_override("pressed", pressed)
	b.custom_minimum_size = Vector2(0, 92)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.set_meta("action_key", key)
	b.pressed.connect(cb)
	parent.add_child(b)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(cc)
	var disc := Control.new()
	disc.custom_minimum_size = Vector2(56, 56)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(disc)
	UI2.plate(disc, "royal", 28.0, "gold", {"rim": 3.0, "shadow_y": 4.0})
	var ic := UI2.icon(disc, icon, 46.0)
	ic.position = Vector2(5, 4)
	if badge > 0:
		UI2.badge(disc, str(badge), Vector2(6, -6))
	var t := UI2.text(v, title, 13, Color.WHITE)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if sub != "":
		var sl := UI.label(v, sub, 10, UI2.CREAM, UI.HEAVY_FONT, true)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sl.autowrap_mode = TextServer.AUTOWRAP_OFF
		sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b

func _lfg_plaque(parent: Node) -> void:
	# LOOKING FOR GROUP: a call in clan chat clanmates JOIN (CANCEL while it's up); a party's member waits for its leader
	var mine: Dictionary = social.lfg_call(str(social.me.get("pid", "")))
	if not social.has_lfg:
		var ob := UI2.button(parent, "LFG COMES WITH THE SERVER UPDATE", "grey", func(): pass, "clan_lfg", 15, 52.0)
		UI2.dim_button(ob, true)
		return
	if not mine.is_empty():
		var r := UI.row(parent, 8)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cb := UI2.button(r, "CALLING YOUR CLAN  ·  %d/%d" % [int(mine.get("size", 1)), int(mine.get("max", 5))], "green", func(): pass, "clan_lfg_up", 17, 54.0, 16.0, UI2.icon_path("horn"))
		UI.grow(cb)
		UI2.pulse(cb, 0.02, 1.2)
		var xb := UI2.button(r, "CANCEL", "ghost", func():
			app.sfx("tap")
			if not social.lfg(false):
				_fail(), "clan_lfg_cancel", 14, 54.0, 16.0)
		xb.custom_minimum_size.x = 100
		return
	var can: bool = not social.in_party() or social.is_leader()
	var lb := UI2.button(parent, "LOOKING FOR GROUP" if can else "YOUR PARTY'S LEADER CALLS", "green", func():
		if not can:
			app.sfx("error")
			app.toast("Only your party's leader can call for players", UI.MUTED)
			return
		app.sfx("confirm")
		if not social.lfg(true):
			_fail(), "clan_lfg", 19, 56.0, 16.0, UI2.icon_path("horn"))
	UI2.dim_button(lb, not can)

func _open_sheet(id: String, again := false) -> void:
	# a sheet over the camp, from just under the clan's name to the bottom: its title, ✕, and what it holds
	if not again:
		app.sfx("menuOpen")
	sheet = id
	var keep := 0
	if is_instance_valid(_scroll) and again:
		keep = _scroll.scroll_vertical
	for ch in _sheet_layer.get_children():
		_sheet_layer.remove_child(ch)
		ch.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent):
		if (ev is InputEventMouseButton or ev is InputEventScreenTouch) and not ev.pressed:
			_close_sheet())
	_sheet_layer.add_child(dim)
	var mc := MarginContainer.new()
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_theme_constant_override("margin_left", 8)
	mc.add_theme_constant_override("margin_right", 8)
	mc.add_theme_constant_override("margin_top", int(maxf(150.0, size.y * 0.2) + float(app.safe_top)))
	mc.add_theme_constant_override("margin_bottom", 10)
	_sheet_layer.add_child(mc)
	var body := UI2.frame(mc, "night", 12, 20.0, "gold")
	body.add_theme_constant_override("separation", 8)
	var hr := UI.row(body, 8)
	var title: String = {"chest":"CLAN CHEST", "shards":"SHARD REQUESTS", "members":"MEMBERS", "league":"CLAN LEAGUE", "clan":"CLAN"}.get(id, "CLAN")
	UI.grow(UI2.text(hr, title, 22, Color.WHITE))
	var xb := UI2.button(hr, "✕", "ghost", func(): _close_sheet(), "clan_sheet_close", 18, 38.0, 12.0)
	xb.custom_minimum_size.x = 46
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
	var c: Dictionary = social.clan
	var hc := bool(c.get("hc", false))
	var role: String = social.clan_role_of_me()
	match id:
		"chest":
			_chest_section(c)
		"shards":
			_shard_section(c)
		"members":
			_members_sheet(c, hc)
		"league":
			_render_league(c)
		_:
			_clan_sheet(c, hc, role)
	if again:
		_scroll.set_deferred("scroll_vertical", keep)

func _close_sheet() -> void:
	app.sfx("menuClose")
	sheet = ""
	for ch in _sheet_layer.get_children():
		_sheet_layer.remove_child(ch)
		ch.queue_free()
	_scroll = null
	_list = null
	if has_meta("drag_scroll"):
		remove_meta("drag_scroll")

func _members_sheet(c: Dictionary, hc: bool) -> void:
	var officer: bool = social.is_clan_officer()
	var req: Array = c.get("req", [])
	if officer and not req.is_empty():
		var rf := _section("REQUESTS", str(req.size()))
		for p in req:
			var r := _member_row(rf, p, "")
			_note_label(r, "Lv %d" % int(p.get("lv", 1)), 12, UI2.CYAN)
			var pp := str(p.pid)
			_small(r, "ACCEPT", "green", "clan_accept_" + pp, func():
				app.sfx("confirm")
				if not social.clan_accept(pp):
					_fail(), 84.0)
			_small(r, "✕", "ghost", "clan_reject_" + pp, func():
				app.sfx("tap")
				social.clan_reject(pp), 44.0)
	_render_members(c, hc)
	if officer:
		var vf := _section("INVITE A PLAYER")
		var vr := UI.row(vf, 8)
		var ve := _field(vr, "invite", "Their friend code", 12)
		ve.text_submitted.connect(func(_t): _invite_code())
		_small(vr, "INVITE", "green", "clan_invite_code", func(): _invite_code(), 90.0)
		UI2.body(vf, "Or tap a player's name anywhere (chat, friends, ranks) and choose INVITE TO CLAN.", 12, UI2.MUTED)

func _clan_sheet(c: Dictionary, hc: bool, role: String) -> void:
	# CLAN: who you are in it; the crest and settings (the leader and officers); a starter clan's way to a players'
	# clan; LEAVE / DISBAND
	var officer: bool = social.is_clan_officer()
	var f := _section("")
	var r := UI.row(f, 10)
	SocialUI.crest(r, str(c.get("cc", "")), 54.0, str(c.get("fr", "")))
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(tv)
	var nl := UI2.text(tv, "[%s] %s" % [str(c.get("tag", "")), str(c.get("name", ""))], 17, Color.WHITE)
	nl.clip_text = true
	var bits := [{"leader":"You lead it", "officer":"You're an officer", "member":"You're a member"}.get(role, ""),
		"%d / %d members" % [int(c.get("n", 0)), int(c.get("max", 30))], str(JOIN_TEXT.get(str(c.get("join", "")), ""))]
	if hc:
		bits = ["A starter clan", "%d member%s" % [int(c.get("n", 0)), "" if int(c.get("n", 0)) == 1 else "s"], "free, open to all"]
	UI2.body(tv, "  ·  ".join(bits), 12, UI2.SOFT)
	if officer and not hc:
		var sf := _section("CREST & SETTINGS")
		var crr := UI.row(sf, 10)
		SocialUI.crest(crr, str(c.get("cc", "")), 46.0, str(c.get("fr", "")))
		UI.grow(UI2.button(crr, "CHANGE CREST", "purple", func(): _edit_crest(Eco.crest_of_code(str(c.get("cc", "")))), "clan_crest_edit", 15, 42.0))
		_settings_rows(sf, c)
	if hc:
		var stf := _section("STARTER CLAN")
		UI2.body(stf, "Starter clans don't fill a Clan Chest or play in the League. Join a players' clan or start your own for a chest every week and League gems -- your shard requests and LFG work here too.", 12, UI2.SOFT)
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
	_leave_section(c, hc, role)

func _chest_section(c: Dictionary) -> void:
	# the CLAN CHEST: the week's points against its four tiers, mine, when the week ends; last week's result
	var pts := int(c.get("pts", 0))
	var tier := Eco.clan_tier(pts)
	var left := int(c.get("ends", 0)) - int(Time.get_unix_time_from_system())
	var f := _section("CLAN CHEST", ("ENDS IN %s" % UI.duration(left)).to_upper() if left > 0 else "")
	var top := UI.row(f, 10)
	var shown := Eco.clan_chest_of(maxi(1, tier))
	var ci := UI2.img(top, Screens.chest_icon(shown), 64.0)
	ci.modulate = Color.WHITE if tier > 0 else Color(0.55, 0.55, 0.62, 0.85)
	ci.set_meta("clan_chest_icon", shown)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tv)
	var head := "%s REACHED" % str(Eco.CHESTS[shown].name).to_upper() if tier > 0 else "NO CHEST YET"
	UI2.text(tv, head, 16, TIER_COL.get(shown, Color.WHITE) if tier > 0 else UI2.SOFT)
	var nxt := tier + 1
	if nxt <= Eco.CLAN_CHEST_TIERS.size():
		var need := int(Eco.CLAN_CHEST_TIERS[nxt - 1][0])
		UI2.body(tv, "%s / %s points to the %s" % [_thousands(pts), _thousands(need), str(Eco.CHESTS[str(Eco.CLAN_CHEST_TIERS[nxt - 1][1])].name)], 12, UI2.SOFT)
	else:
		UI2.body(tv, "%s points -- the best chest there is!" % _thousands(pts), 12, UI2.GREEN)
	var top_pts := float(Eco.CLAN_CHEST_TIERS[Eco.CLAN_CHEST_TIERS.size() - 1][0])
	var bar := UI2.bar(f, minf(float(pts), top_pts), top_pts, Color("#ffe9a6"), Color("#e09a2a"), 14.0)
	bar.set_meta("clan_chest_bar", pts)
	# the tiers under the bar, each at its points
	var marks := Control.new()
	marks.custom_minimum_size = Vector2(0, 30)
	marks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.add_child(marks)
	for i in Eco.CLAN_CHEST_TIERS.size():
		var t: Array = Eco.CLAN_CHEST_TIERS[i]
		var lab := UI.label(marks, "%s\n%d" % [str(t[1]).to_upper(), int(t[0])], 9, TIER_COL.get(str(t[1]), Color.WHITE) if tier > i else UI2.MUTED, UI.HEAVY_FONT)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.autowrap_mode = TextServer.AUTOWRAP_OFF
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var frac := float(t[0]) / top_pts
		var place := func():
			lab.size = lab.get_combined_minimum_size()
			lab.position = Vector2(clampf(marks.size.x * frac - lab.size.x * 0.5, 0.0, marks.size.x - lab.size.x), 0.0)
		marks.resized.connect(place)
		place.call_deferred()
	var mine := int(c.get("mine_pts", 0))
	var ok := mine >= Eco.CLAN_CHEST_MIN
	UI2.body(f, ("Your points this week: %d -- the chest is yours on Monday." if ok else "Your points this week: %d -- earn %d to get the chest on Monday.") % [mine, Eco.CLAN_CHEST_MIN],
		12, UI2.GREEN if ok else UI2.SOFT)
	UI2.body(f, "Every online match earns points: a win 10, a draw 6, a loss 4, +2 a tower, +1 a KO. Doubled with a clanmate in your party!", 11, UI2.MUTED)
	var last: Dictionary = c.get("last", {})
	if int(last.get("pts", 0)) > 0:
		var bits := ["%s points" % _thousands(int(last.pts))]
		if str(last.get("chest", "")) != "":
			bits.append(str(Eco.CHESTS.get(str(last.chest), {}).get("name", "")))
		bits.append("League #%d%s" % [int(last.get("rank", 0)), (" (+%d gems)" % int(last.gems)) if int(last.get("gems", 0)) > 0 else ""])
		UI2.body(f, "Last week: " + ",  ".join(bits), 12, UI2.CYAN)

func _shard_section(c: Dictionary) -> void:
	var f := _section("SHARD REQUESTS")
	var p = app.profile
	var me_pid := str(social.me.get("pid", ""))
	var mine: Dictionary = social.my_ask()
	if not mine.is_empty():
		var r := UI.row(f, 8)
		UI2.img(r, "res://assets/ui/skins/default_%s.png" % str(mine.h), 40.0)
		UI.grow(UI2.body(r, "You asked for a %s shard. A clanmate who has one can give it." % _hero(str(mine.h)), 12, UI2.SOFT))
		_small(r, "TAKE BACK", "ghost", "clan_shard_back", func():
			app.sfx("tap")
			if not social.clan_unask():
				_fail(), 96.0)
	else:
		var wait := int(c.get("ask_next", 0)) - int(Time.get_unix_time_from_system())
		var ab := UI2.button(f, "ASK FOR A SHARD" if wait <= 0 else "NEXT ASK IN %s" % UI.duration(wait).to_upper(), "purple", func():
			if wait > 0:
				app.sfx("error")
				app.toast("You can ask again in %s" % UI.duration(wait), UI.MUTED)
				return
			_pick_hero(), "clan_shard_ask", 15, 42.0)
		UI2.dim_button(ab, wait > 0)
	var others := (c.get("asks", []) as Array).filter(func(a): return str(a.get("pid", "")) != me_pid)
	if others.is_empty():
		UI2.body(f, "Ask your clan for a shard of a hero you don't have yet; give clanmates the ones you hold and get their melt gold.", 11, UI2.MUTED)
	for a in others:
		var h := str(a.get("h", ""))
		var pid := str(a.get("pid", ""))
		var r := UI.row(f, 8)
		UI2.img(r, "res://assets/ui/skins/default_%s.png" % h, 40.0)
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", -2)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(tv)
		var nl := UI2.text(tv, str(a.get("n", "Player")), 14, Color.WHITE)
		nl.clip_text = true
		UI2.body(tv, "needs a %s shard" % _hero(h), 11, UI2.SOFT)
		var have: bool = p.giftable_shards(h) > 0
		var gb := _small(r, ("GIVE +%d" % Eco.shard_melt_gold(h, p.now())) if have else "NO SHARD", "green" if have else "grey", "clan_shard_give_" + pid, func():
			if not have:
				app.sfx("error")
				app.toast(("Your %s shard was a clanmate's gift -- it can't be given on" if p.shards_of(h) > 0 else "You don't have a %s shard") % _hero(h), UI.MUTED)
				return
			app.sfx("confirm")
			if not social.clan_give(pid):
				_fail(), 108.0)
		UI2.dim_button(gb, not have)

func _pick_hero() -> void:
	# ASK FOR A SHARD: the heroes this player doesn't own
	var v := _open_overlay("ASK FOR A SHARD")
	UI2.center(UI2.body(v, "Which hero? Your clan sees the request for 24 hours.", 12, UI2.SOFT))
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	v.add_child(g)
	var n := 0
	for h in Eco.HERO_PRICES:
		var hid := str(h)
		if app.profile.owns_hero(hid):
			continue
		n += 1
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(cell)
		var im := UI2.img(cell, "res://assets/ui/skins/default_%s.png" % hid, 72.0)
		im.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		UI2.button(cell, _hero(hid).to_upper(), "purple", func():
			if social.clan_ask(hid):
				app.sfx("confirm")
				_close_overlay()
			else:
				_fail(), "clan_shard_" + hid, 11, 32.0, 9.0)
	if n == 0:
		UI2.center(UI2.body(v, "You have every hero already!", 13, UI2.GREEN))
	UI2.button(v, "CLOSE", "ghost", func():
		app.sfx("menuClose")
		_close_overlay(), "clan_shard_close", 14, 36.0)

static func _hero(hid: String) -> String:
	return str(Screens.HERO_NAMES.get(hid, hid.capitalize()))

func _settings_rows(sf: VBoxContainer, c: Dictionary) -> void:
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

func _leave_section(c: Dictionary, hc: bool, role: String) -> void:
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
		note = "Leaving a starter clan has no wait."
	if role == "leader":
		note += " If you leave, an officer takes over."
	UI2.body(lf, note, 12, UI2.MUTED)

func _render_members(c: Dictionary, hc: bool) -> void:
	var role: String = social.clan_role_of_me()
	var shown: int = (c.get("members", []) as Array).size()
	var mf := _section("MEMBERS", ("%d / %d" % [int(c.get("n", 0)), int(c.get("max", 30))]) if not hc
		else ("%d" % int(c.get("n", 0)) if shown >= int(c.get("n", 0)) else "%d SHOWN OF %d" % [shown, int(c.get("n", 0))]))
	if not hc:
		UI2.body(mf, "Points this week beside each name -- %d+ gets the Clan Chest." % Eco.CLAN_CHEST_MIN, 11, UI2.MUTED)
	for m in c.get("members", []):
		var mrole := str(m.get("role", "member"))
		var r := _member_row(mf, m, mrole)
		var mp := str(m.pid)
		if not hc:
			var wp := int(m.get("wp", 0))
			var pl := _note_label(r, "%d pts" % wp, 12, UI2.GREEN if wp >= Eco.CLAN_CHEST_MIN else UI2.MUTED)
			pl.custom_minimum_size.x = 52
			pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if mp == str(social.me.get("pid", "")):
			_note_label(r, "YOU", 12, UI2.GREEN)
		elif role == "leader" or (role == "officer" and mrole == "member"):
			var mc: Dictionary = m.duplicate()
			_small(r, "MANAGE", "blue", "clan_manage_" + mp, func(): _manage(mc), 92.0)

func _render_league(c: Dictionary) -> void:
	var lg: Dictionary = social.league
	var now := Time.get_ticks_msec() / 1000.0
	if (lg.is_empty() or float(social._clock) - float(lg.get("_at", -999.0)) > LEAGUE_STALE) and now - _league_asked > LEAGUE_STALE:
		_league_asked = now                      # (asked once in a while: the answer redraws the window)
		social.clan_league()
	var left := int(lg.get("ends", c.get("ends", 0))) - int(Time.get_unix_time_from_system())
	var f := _section("CLAN LEAGUE", ("ENDS IN %s" % UI.duration(left)).to_upper() if left > 0 else "")
	UI2.body(f, "Clans ranked by this week's points. On Monday every member with %d+ points gets the prize:" % Eco.CLAN_CHEST_MIN, 12, UI2.SOFT)
	var pr := UI.row(f, 6)
	for p in Eco.CLAN_LEAGUE_PRIZES:
		var rank := "#%d" % int(p.from) if int(p.from) == int(p.to) else "#%d-%d" % [int(p.from), int(p.to)]
		var col: Color = FRAME_COL.get(str(p.frame), UI2.SOFT)
		var chip := UI2.chip(pr, "%s  %d GEMS" % [rank, int(p.gems)], Color(0.05, 0.07, 0.16, 0.9), col, col.darkened(0.4))
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI2.body(f, "The top three wear a gold, silver or bronze frame round their crest all next week.", 11, UI2.MUTED)
	var tf := _section("THIS WEEK", "%d CLANS" % int(lg.get("clans", 0)) if not lg.is_empty() else "")
	var rows: Array = lg.get("list", [])
	if lg.is_empty():
		UI2.body(tf, "Loading...", 13, UI2.MUTED)
	elif rows.is_empty():
		UI2.body(tf, "No clan has points yet this week -- play an online match to put yours on top!", 13, UI2.MUTED)
	for row in rows:
		_league_row(tf, row)
	var me_row: Dictionary = lg.get("me", {})
	if not lg.is_empty() and not bool(c.get("hc", false)):
		if me_row.is_empty():
			UI2.body(tf, "Your clan: no points yet this week.", 12, UI2.SOFT)
		elif int(me_row.get("rank", 0)) > rows.size():
			_league_row(tf, me_row)
	var last: Array = lg.get("last", [])
	if not last.is_empty():
		var lf := _section("LAST WEEK'S PODIUM")
		for i in last.size():
			var x: Dictionary = last[i]
			var r := UI.row(lf, 8)
			_note_label(r, "#%d" % (i + 1), 15, FRAME_COL.get(str(x.get("fr", "")), Color.WHITE))
			SocialUI.crest(r, str(x.get("cc", "")), 30.0, str(x.get("fr", "")))
			var nl := UI2.text(r, "[%s] %s" % [str(x.get("tag", "")), str(x.get("name", ""))], 14, Color.WHITE)
			nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nl.clip_text = true
			_note_label(r, "%s pts" % _thousands(int(x.get("pts", 0))), 12, UI2.SOFT)

func _league_row(parent: Node, row: Dictionary) -> void:
	var you := bool(row.get("you", false))
	var pc := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.1, 0.3, 0.12, 0.55) if you else Color(0.0, 0.02, 0.08, 0.35)
	st.border_color = Color(0.55, 0.94, 0.66, 0.6) if you else Color(0.5, 0.65, 0.95, 0.15)
	st.set_border_width_all(1)
	st.set_corner_radius_all(10)
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 3
	st.content_margin_bottom = 3
	pc.add_theme_stylebox_override("panel", st)
	pc.set_meta("league_row", int(row.get("rank", 0)))
	parent.add_child(pc)
	var r := UI.row(pc, 8)
	var rk := _note_label(r, "#%d" % int(row.get("rank", 0)), 15, FRAME_COL.get(str(row.get("fr", "")), Color.WHITE) if int(row.get("rank", 0)) > 3 else
		FRAME_COL[["gold", "silver", "bronze"][int(row.get("rank", 1)) - 1]])
	rk.custom_minimum_size.x = 34
	SocialUI.crest(r, str(row.get("cc", "")), 30.0, str(row.get("fr", "")))
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", -3)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(tv)
	var nl := UI2.text(tv, "[%s] %s" % [str(row.get("tag", "")), str(row.get("name", ""))], 14, SocialUI.NAME_ME if you else Color.WHITE)
	nl.clip_text = true
	var sl := UI.label(tv, "Level %d  ·  %d members" % [int(row.get("lv", 1)), int(row.get("n", 0))], 10, UI2.MUTED, UI.HEAVY_FONT)
	sl.autowrap_mode = TextServer.AUTOWRAP_OFF
	_note_label(r, "%s pts" % _thousands(int(row.get("pts", 0))), 13, UI2.CREAM)

# ---------------- in a clan, an older server (0.31.134-0.31.195) ----------------
func _render_mine_old() -> void:
	var c: Dictionary = social.clan
	var house := str(c.get("house", ""))
	var role: String = social.clan_role_of_me()
	var officer: bool = social.is_clan_officer()
	var hc := bool(c.get("hc", false))
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
	UI2.body(bf, "The clan camp, crest, Clan Chest, League, shard requests and LFG arrive with the next server update.", 12, UI2.MUTED)
	var cr := UI.row(bf, 8)
	var n := int(social.unread.get("clan", 0))
	UI.grow(UI2.button(cr, "CLAN CHAT" + ("  (%d)" % n if n > 0 else ""), "orange", func():
		app.sfx("menuOpen")
		app.open_chat("clan"), "clan_chat", 16, 44.0))
	var req: Array = c.get("req", [])
	if officer and not req.is_empty():
		var rf := _section("REQUESTS", str(req.size()))
		for p in req:
			var r := _member_row(rf, p, "")
			var pp := str(p.pid)
			_small(r, "ACCEPT", "green", "clan_accept_" + pp, func():
				app.sfx("confirm")
				if not social.clan_accept(pp):
					_fail(), 84.0)
			_small(r, "✕", "ghost", "clan_reject_" + pp, func():
				app.sfx("tap")
				social.clan_reject(pp), 44.0)
	if officer:
		var vf := _section("INVITE A PLAYER")
		var vr := UI.row(vf, 8)
		var ve := _field(vr, "invite", "Their friend code", 12)
		ve.text_submitted.connect(func(_t): _invite_code())
		_small(vr, "INVITE", "green", "clan_invite_code", func(): _invite_code(), 90.0)
	_render_members(c, hc)
	if officer:
		_settings_rows(_section("SETTINGS"), c)
	_leave_section(c, hc, role)

# ---------------- members ----------------
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
		_note_label(top, "OFFICER", 11, UI2.CYAN)
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
	var v := _open_overlay(str(m.get("n", "Player")), 320.0)
	var pid := str(m.get("pid", ""))
	var role := str(m.get("role", "member"))
	var mine: String = social.clan_role_of_me()
	UI2.center(UI2.body(v, {"officer":"Officer", "member":"Member"}.get(role, ""), 13, UI2.MUTED))
	var done := func(ok: bool) -> void:
		if not ok:
			_fail()
		_close_overlay()
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
		_close_overlay(), "clan_m_close", 14, 36.0)

# ---------------- text ----------------
static func _hours(secs: int) -> String:
	var h := int(ceil(secs / 3600.0))
	return "%d hour%s" % [h, "" if h == 1 else "s"]

static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out
