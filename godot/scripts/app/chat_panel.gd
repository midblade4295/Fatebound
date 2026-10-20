extends Control
# 0.31.111 (Kevin: "Build a global chat and players can click a name and have option to add friend"): the chat window.
# GLOBAL (everyone online) and PARTY tabs, the lines (tap a name for its card: add friend, invite, block, report),
# and a text field with SEND. The sheet rises above the phone's keyboard while it's open. Lines arrive live from
# scripts/meta/social.gd; the tab on screen counts as read.
# 0.31.196: the crest before a clan member's name; in CLAN, a shard request's line has GIVE (if you hold that hero's
# shard; TAKE BACK on your own) and an LFG call's line JOIN (CANCEL on your own) while they're open.
const UI = preload("res://scripts/app/ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")
const SocialUI = preload("res://scripts/app/social_ui.gd")
const Eco = preload("res://scripts/meta/economy.gd")

var app
var social
var ch := "global"
var _margin: MarginContainer
var _list: VBoxContainer
var _scroll: ScrollContainer
var _input: LineEdit
var _tabs := {}
var _status: Label
var _shown := 0                       # lines of `ch` on screen
var _shown_first := {}                # the first line on screen (history replaced -> redraw)
var _shown_last := {}                 # 0.31.140: the last line on screen (lines merged in before it -> redraw)
var _shown_ch := ""                   # the channel on screen
var _bottom := 24.0
var _stick := true                    # follow new lines (the list is at its bottom)
var _live: Array = []                 # 0.31.196: [button, line] -- a request's GIVE, a call's JOIN (kept up to date)

func open(a, start_ch := "global") -> void:
	app = a
	social = a.social
	ch = start_ch if (start_ch == "party" and social.in_party()) or (start_ch == "clan" and social.in_clan()) else ("global" if social.show_global else "party")
	_build()
	social.changed.connect(_on_changed)
	social.viewing = ch
	social.mark_read(ch)
	_render()

func _exit_tree() -> void:
	if social != null and social.viewing == ch:
		social.viewing = ""

func _build() -> void:
	var w := SocialUI.window(self, "CHAT", "chat", func():
		app.sfx("menuClose")
		app.close_modal(), 56.0 + float(app.safe_top), _bottom)
	_margin = w.margin
	var body: VBoxContainer = w.body
	var tr := UI.row(body, 8)
	for t in [["global", "GLOBAL"], ["party", "PARTY"], ["clan", "CLAN"]]:       # (0.31.134: CLAN)
		var id: String = t[0]
		var b := UI2.button(tr, t[1], "gold", func(): _switch(id), "chat_tab_" + id, 15, 38.0, 12.0)
		UI.grow(b)
		_tabs[id] = b
	_status = UI2.body(body, "", 12, UI2.MUTED)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.scroll_deadzone = 1000000                 # (drag-scrolled by the app's _input, like the menus)
	body.add_child(_scroll)
	set_meta("drag_scroll", _scroll)
	_scroll.get_v_scroll_bar().value_changed.connect(func(_v):
		var bar := _scroll.get_v_scroll_bar()
		_stick = bar.value >= bar.max_value - bar.page - 24.0)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	var ir := UI.row(body, 8)
	_input = SocialUI.field(ir, "Say something...", 120)
	_input.text_submitted.connect(func(_t): _send())
	var sb := UI2.button(ir, "SEND", "orange", func(): _send(), "chat_send", 16, 46.0, 14.0)
	sb.custom_minimum_size.x = 86

func _switch(id: String) -> void:
	if id == ch:
		return
	if id == "party" and not social.in_party():
		app.sfx("error")
		app.toast("Invite a friend to a party first -- tap their name, or open Friends", UI.MUTED)
		return
	if id == "clan" and not social.in_clan():
		app.sfx("error")
		app.toast("Join a clan first -- FRIENDS on Home, then CLAN", UI.MUTED)
		return
	if id == "global" and not social.show_global:
		app.sfx("error")
		app.toast("Global chat is off -- turn it on in Settings", UI.MUTED)
		return
	app.sfx("tab")
	ch = id
	social.viewing = ch
	social.mark_read(ch)
	_shown = 0
	_render()

func _send() -> void:
	var t := _input.text.strip_edges()
	if t == "":
		return
	if social.say(ch, t):
		app.sfx("tap")
		_input.text = ""
		_stick = true
	else:
		app.sfx("error")
		app.toast("Not connected to chat right now", UI.RED)

func _on_changed(what: String) -> void:
	if (what == "party" and ch == "party" and not social.in_party()) or (what == "clan" and ch == "clan" and not social.in_clan()):
		ch = "global"
		social.viewing = ch
		_shown = 0
	if what in ["chat", "party", "state", "me", "clan"]:
		if social.viewing == ch:
			social.unread[ch] = 0
		_render()
		_live_update()

func _render() -> void:
	# tabs: the one open is gold; PARTY greys out without a party; unread counts on the other
	for id in _tabs:
		var b: Button = _tabs[id]
		var on: bool = id == ch
		var n := int(social.unread.get(id, 0))
		var label: String = {"global":"GLOBAL", "party":"PARTY", "clan":"CLAN"}[id]
		if id == "party" and social.in_party():
			label = "PARTY %d/%d" % [social.party_size(), int(social.party.get("max", 4))]
		b.text = label + ("  (%d)" % n if n > 0 and not on else "")
		b.modulate = Color.WHITE if on else Color(0.72, 0.76, 0.86, 0.9)
		if id == "clan":
			b.modulate.a = 1.0 if social.in_clan() else 0.45
		if id == "party":
			b.visible = true
			b.modulate.a = 1.0 if social.in_party() else 0.45
		if id == "global":
			b.modulate.a = 1.0 if social.show_global else 0.45
	match str(social.state):
		"online": _status.text = ""
		"connecting": _status.text = "Connecting to chat..."
		"old": _status.text = "Chat arrives with the next server update."
		_: _status.text = "Chat connects once you're online with the game's server." if not social.has_account() else "Not connected -- trying again shortly..."
	_status.visible = _status.text != ""
	var lines: Array = social.lines.get(ch, [])
	var first: Dictionary = lines[0] if not lines.is_empty() else {}
	var at_end: Dictionary = lines[_shown - 1] if _shown > 0 and _shown <= lines.size() else {}
	if ch != _shown_ch or _shown > lines.size() or first != _shown_first or at_end != _shown_last:
		for c in _list.get_children():
			c.queue_free()
		_live = []
		_shown = 0
		_shown_first = first
		_shown_ch = ch
	if lines.is_empty() and _list.get_child_count() == 0:
		var e := UI2.body(_list, {"global":"Nobody's said anything yet -- say hi!", "party":"Talk to your party here.", "clan":"Talk to your clan here."}[ch], 13, UI2.MUTED)
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		e.set_meta("empty", true)
	for i in range(_shown, lines.size()):
		for c in _list.get_children():
			if c.has_meta("empty"):
				c.queue_free()
		_row(lines[i])
	_shown = lines.size()
	_shown_last = lines[_shown - 1] if _shown > 0 else {}
	if _stick:
		_to_bottom.call_deferred()

func _to_bottom() -> void:
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)

func _row(l: Dictionary) -> void:
	if bool(l.get("sys", false)):
		var s := UI2.body(_list, "— %s —" % str(l.get("x", "")), 12, Color("#c8b88a"))
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return
	var mine: bool = str(l.get("pid", "")) == str(social.me.get("pid", ""))
	var pc := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.36, 0.22, 0.04, 0.5) if mine else Color(0.0, 0.02, 0.08, 0.42)
	st.border_color = Color(0.97, 0.8, 0.33, 0.35) if mine else Color(0.5, 0.65, 0.95, 0.18)
	st.set_border_width_all(1)
	st.set_corner_radius_all(12)
	st.content_margin_left = 10
	st.content_margin_right = 10
	st.content_margin_top = 4
	st.content_margin_bottom = 6
	pc.add_theme_stylebox_override("panel", st)
	_list.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	pc.add_child(v)
	var head := UI.row(v, 6)
	var nb := Button.new()
	nb.flat = true
	nb.focus_mode = Control.FOCUS_NONE
	nb.text = str(l.get("n", "Player"))
	if str(l.get("ct", "")) != "":
		nb.text = "[%s] %s" % [str(l.ct), nb.text]          # 0.31.134: their clan's tag
	nb.add_theme_font_override("font", UI.HEAVY_FONT)
	nb.add_theme_font_size_override("font_size", 14)
	var col: Color = SocialUI.NAME_ME if mine else SocialUI.NAME_OTHER
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		nb.add_theme_color_override(k, col)
	nb.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	nb.add_theme_constant_override("outline_size", 3)
	for st_name in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		var e := StyleBoxEmpty.new()
		e.content_margin_left = 0
		e.content_margin_right = 4
		nb.add_theme_stylebox_override(st_name, e)
	nb.set_meta("action_key", "chat_name")
	var card := {"pid":str(l.get("pid", "")), "n":str(l.get("n", "")), "tt":str(l.get("tt", "")), "ct":str(l.get("ct", ""))}
	nb.pressed.connect(func(): SocialUI.name_card(app, self, card))
	if str(l.get("cc", "")) != "":
		SocialUI.crest(head, str(l.cc), 20.0)          # 0.31.196: their clan's crest
	head.add_child(nb)
	SocialUI.title_label(head, str(l.get("tt", "")), 11)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(sp)
	var tl := UI.label(head, SocialUI.ago(int(Time.get_unix_time_from_system()) - int(l.get("at", 0))), 10, UI2.MUTED, UI.HEAVY_FONT)
	tl.autowrap_mode = TextServer.AUTOWRAP_OFF
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var x := UI.label(v, str(l.get("x", "")), 15, Color.WHITE, UI.BODY_FONT)
	x.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	x.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ch == "clan" and (l.has("ask") or l.has("lfg")):
		# 0.31.196: a shard request (GIVE) or an LFG call (JOIN), live while it's open
		var b := UI2.button(v, "", "green", func(): _act(l), "chat_give" if l.has("ask") else "chat_lfg_join", 13, 34.0, 10.0)
		b.size_flags_horizontal = Control.SIZE_SHRINK_END
		b.custom_minimum_size.x = 150
		_live.append([b, l])
		_live_one(b, l)

func _live_update() -> void:
	for e in _live:
		if is_instance_valid(e[0]):
			_live_one(e[0], e[1])

func _live_one(b: Button, l: Dictionary) -> void:
	var pid := str(l.get("pid", ""))
	var mine: bool = pid == str(social.me.get("pid", ""))
	var text := ""
	var on := false
	var col := "green"
	if l.has("ask"):
		var h := str(l.ask)
		if social.ask_open(pid, h):
			if mine:
				text = "TAKE BACK"
				col = "ghost"
				on = true
			elif app.profile.giftable_shards(h) > 0:
				text = "GIVE  +%d GOLD" % Eco.shard_melt_gold(h, app.profile.now())
				on = true
			else:
				text = "NO SHARD TO GIVE"
				col = "grey"
	else:
		var call: Dictionary = social.lfg_call(str(l.lfg))
		if not call.is_empty() and absi(int(call.get("at", 0)) - int(l.get("at", 0))) < 5:
			if mine:
				text = "CANCEL CALL"
				col = "ghost"
				on = true
			elif social.in_my_party(pid):
				text = "IN YOUR PARTY"
				col = "grey"
			else:
				text = "JOIN  %d/%d" % [int(call.get("size", 1)), int(call.get("max", 5))]
				on = true
	b.visible = text != ""
	if text != "" and (b.text != text or str(b.get_meta("col", "")) != col):
		b.text = text
		b.set_meta("col", col)
		UI2.dim_button(b, not on)
	b.set_meta("on", on)

func _act(l: Dictionary) -> void:
	var b: Button = null
	for e in _live:
		if e[1] == l and is_instance_valid(e[0]):
			b = e[0]
	if b == null or not bool(b.get_meta("on", false)):
		app.sfx("error")
		return
	var pid := str(l.get("pid", ""))
	var mine: bool = pid == str(social.me.get("pid", ""))
	var ok := false
	if l.has("ask"):
		ok = social.clan_unask() if mine else social.clan_give(pid)
	else:
		ok = social.lfg(false) if mine else social.lfg_join(str(l.lfg))
	if ok:
		app.sfx("confirm")
	else:
		app.sfx("error")
		app.toast("Not connected to the server right now", UI.RED)

func _process(_delta: float) -> void:
	# keep the field above the keyboard (its height is in window pixels: turned into this canvas's)
	var kh := float(DisplayServer.virtual_keyboard_get_height())
	var want := 24.0
	if kh > 0.0:
		var win := float(DisplayServer.window_get_size().y)
		var scale := get_viewport_rect().size.y / maxf(1.0, win)
		want = kh * scale + 8.0
	if absf(want - _bottom) > 1.0:
		_bottom = want
		_margin.add_theme_constant_override("margin_bottom", int(_bottom))
		if _stick:
			_to_bottom.call_deferred()
