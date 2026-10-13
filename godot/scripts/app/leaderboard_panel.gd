extends Control
# 0.31.119 (Kevin: "Do all" -- 4. leaderboards): the LEADERBOARD window from Home's RANKS medallion. The server keeps the
# week's points from online matches (server/leaderboard.gd); this asks for them (lb_fetch.gd) and shows WEEKLY (the
# top 50, your row pinned under them when you're further down) or FRIENDS (you and your friends), when the week ends,
# last week's champions and how points are earned.
const UI = preload("res://scripts/app/ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")
const SocialUI = preload("res://scripts/app/social_ui.gd")
const LbFetch = preload("res://scripts/meta/lb_fetch.gd")
const NetT = preload("res://scripts/siege/siege_net.gd")
const Eco = preload("res://scripts/meta/economy.gd")

const MEDAL := [Color("#ffc23d"), Color("#d8e2ea"), Color("#e09056")]       # gold, silver, bronze
const TITLE_COL := {"common": Color("#cfd8e0"), "rare": Color("#6cc4ff"), "epic": Color("#d6a2ff"), "legendary": Color("#ffc23d")}

var app
var tab := "week"                   # "week" / "friends"
var data := {}                      # the server's answer ({} until it comes; {"_fail": true} when it didn't)
var _list: VBoxContainer
var _scroll: ScrollContainer
var _tab_row: HBoxContainer

func open(a) -> void:
	app = a
	var w := SocialUI.window(self, "LEADERBOARD", "trophy", func():
		app.sfx("menuClose")
		app.close_modal(), 56.0 + float(app.safe_top), 24.0)
	_tab_row = UI.row(w.body, 8)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.scroll_deadzone = 1000000                 # (drag-scrolled by the app, like the menus)
	(w.body as VBoxContainer).add_child(_scroll)
	set_meta("drag_scroll", _scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	_render()
	var acct := str(app.profile.d.account.get("id", ""))
	var key := str(app.profile.d.account.get("key", ""))
	if acct == "" or key == "":
		data = {"_fail": true, "_why": "account"}
		_render()
		return
	LbFetch.start(self, str(app.eco_url), acct, key, func(r: Dictionary):
		data = r if not r.is_empty() else {"_fail": true}
		if is_inside_tree():
			_render())

func _render() -> void:
	# the tabs: the open one gold, the other blue
	for c in _tab_row.get_children():
		_tab_row.remove_child(c)
		c.queue_free()
	for t in [["week", "THIS WEEK"], ["friends", "FRIENDS"]]:
		var b := UI2.button(_tab_row, str(t[1]), "gold" if tab == str(t[0]) else "blue", func():
			if tab == str(t[0]):
				return
			app.sfx("tab")
			tab = str(t[0])
			_render(), "lb_tab_" + str(t[0]), 15, 40.0, 12.0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	if data.is_empty():
		UI2.center(UI2.body(_list, "Loading the week's best...", 14, UI2.SOFT))
		return
	if bool(data.get("_fail", false)):
		var why := "Play an online match first -- your account is made then." if str(data.get("_why", "")) == "account" \
			else "Couldn't reach the Siege server. Try again in a moment."
		UI2.center(UI2.body(_list, why, 14, UI2.SOFT))
		return
	# when the week ends
	var left := maxi(0, int(data.get("ends", 0)) - int(Time.get_unix_time_from_system()))
	var head := UI.row(_list, 6)
	var hl := UI2.text(head, "WEEK OF %s" % _date(str(data.get("week", ""))), 14, UI2.GOLD)
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI2.body(head, "ends in %s" % _left(left), 12, UI2.SOFT, false)
	var rows: Array = data.get("top", []) if tab == "week" else data.get("friends", [])
	if rows.is_empty():
		if tab == "week":
			UI2.center(UI2.body(_list, "Nobody's on the board yet this week -- win an online match and be first.", 13, UI2.SOFT))
		else:
			UI2.center(UI2.body(_list, "Play an online match to get on the board, and add friends to see how you compare.", 13, UI2.SOFT))
	else:
		_header(_list)
		for r in rows:
			_row(_list, r)
	var me: Dictionary = data.get("me", {})
	if tab == "week" and not me.is_empty() and int(me.get("rank", 0)) > rows.size():
		UI2.center(UI2.body(_list, "· · ·", 12, UI2.MUTED, false))
		_row(_list, me)
	elif me.is_empty() and tab == "week" and not rows.is_empty():
		UI2.center(UI2.body(_list, "You're not on the board yet -- play an online match.", 12, UI2.SOFT))
	if tab == "friends":
		var fb := UI2.button(_list, "FRIENDS", "blue", func():
			app.sfx("menuOpen")
			app.open_friends(), "lb_friends", 15, 42.0, 12.0)
		fb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		fb.custom_minimum_size.x = 160
	if tab == "week":
		_prizes(_list)
	# last week's champions
	var last: Array = data.get("last", [])
	if not last.is_empty():
		var f := UI2.frame(_list, "royal", 10, 14.0, "gold", {"pattern_mix": 0.0})
		UI2.center(UI2.text(f, "LAST WEEK'S CHAMPIONS", 14, UI2.GOLD))
		for i in last.size():
			var c: Dictionary = last[i]
			var lr := UI.row(f, 6)
			var ml := UI.label(lr, "%d" % (i + 1), 14, MEDAL[i], UI.HEAVY_FONT)
			ml.autowrap_mode = TextServer.AUTOWRAP_OFF
			ml.custom_minimum_size.x = 18
			var nl := UI.label(lr, NetT.title_text(str(c.get("name", "")), str(c.get("title", ""))), 13, Color.WHITE, UI.HEAVY_FONT)
			nl.autowrap_mode = TextServer.AUTOWRAP_OFF
			nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nl.clip_text = true
			var pl := UI.label(lr, "%d pts" % int(c.get("pts", 0)), 12, UI2.SOFT, UI.HEAVY_FONT)
			pl.autowrap_mode = TextServer.AUTOWRAP_OFF
	UI2.center(UI2.body(_list, "Points come from online matches: rescue 300 · KO 20 · fish fed 30 · gathering 2 · gate damage ÷10 · a win +100. A new week starts every Monday (UTC).", 11, UI2.MUTED))
	UI2.center(UI2.body(_list, "%d player%s on the board" % [int(data.get("players", 0)), "" if int(data.get("players", 0)) == 1 else "s"], 11, UI2.MUTED, false))

func _header(parent: Node) -> void:
	var h := UI.row(parent, 4)
	var a := UI.label(h, "PLAYER", 10, UI2.MUTED, UI.HEAVY_FONT)
	a.autowrap_mode = TextServer.AUTOWRAP_OFF
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for hh in [["WINS", 40], ["♛", 28], ["PTS", 56]]:
		var l := UI.label(h, str(hh[0]), 10, UI2.MUTED, UI.HEAVY_FONT)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.custom_minimum_size.x = float(hh[1])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

func _row(parent: Node, r: Dictionary) -> void:
	var mine := bool(r.get("you", false))
	var rank := int(r.get("rank", 0))
	var box := PanelContainer.new()
	box.name = "LbRow"
	box.set_meta("rank", rank)
	box.set_meta("you", mine)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(UI2.GOLD, 0.2) if mine else Color(1, 1, 1, 0.05)
	st.set_corner_radius_all(10)
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 4
	st.content_margin_bottom = 4
	if mine:
		st.border_color = UI2.GOLD
		st.set_border_width_all(1)
	elif rank >= 1 and rank <= 3:
		st.border_color = Color(MEDAL[rank - 1], 0.6)
		st.set_border_width_all(1)
	box.add_theme_stylebox_override("panel", st)
	parent.add_child(box)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	box.add_child(h)
	var rk := UI.label(h, str(rank), 15 if rank <= 3 else 13, MEDAL[rank - 1] if rank >= 1 and rank <= 3 else UI2.MUTED, UI.HEAVY_FONT)
	rk.autowrap_mode = TextServer.AUTOWRAP_OFF
	rk.custom_minimum_size.x = 30
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(col)
	var nl := UI.label(col, str(r.get("name", "Player")) + ("  (you)" if mine else ""), 14, UI2.GOLD if mine else Color.WHITE, UI.HEAVY_FONT)
	nl.autowrap_mode = TextServer.AUTOWRAP_OFF
	nl.clip_text = true
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var tid := str(r.get("title", ""))
	if tid != "" and NetT.TITLES.has(tid):
		var tl := UI.label(col, str(NetT.TITLES[tid][0]), 10, TITLE_COL.get(NetT.title_rarity(tid), Color.WHITE), UI.HEAVY_FONT)
		tl.autowrap_mode = TextServer.AUTOWRAP_OFF
	if r.has("q") and not bool(r.q):
		# 0.31.120: not in the running for a prize yet
		var ql := UI.label(col, "%d more match%s for a prize" % [Eco.LB_MIN_MATCHES - int(r.get("m", 0)), "" if Eco.LB_MIN_MATCHES - int(r.get("m", 0)) == 1 else "es"], 10, UI2.MUTED, UI.HEAVY_FONT)
		ql.autowrap_mode = TextServer.AUTOWRAP_OFF
	for v in [[str(int(r.get("w", 0))), 40], [str(int(r.get("r", 0))), 28], [str(int(r.get("pts", 0))), 56]]:
		var l := UI.label(h, str(v[0]), 14, Color.WHITE, UI.HEAVY_FONT)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.custom_minimum_size.x = float(v[1])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# 0.31.120 (Kevin: player profile card): tap a player's row for their card (add them as a friend from it)
	var pid := str(r.get("pid", ""))
	if pid != "" and not mine and app.social != null and app.social.online():
		var tap := Button.new()
		tap.flat = true
		tap.focus_mode = Control.FOCUS_NONE
		for st_name in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
			tap.add_theme_stylebox_override(st_name, StyleBoxEmpty.new())
		tap.set_meta("action_key", "lb_card_%d" % rank)
		var card := {"pid":pid, "n":str(r.get("name", "Player")), "tt":str(r.get("title", ""))}
		tap.pressed.connect(func(): SocialUI.name_card(app, self, card))
		box.add_child(tap)

func _prizes(parent: Node) -> void:
	# 0.31.120: what the week's best win (paid by the server when the week ends)
	var f := UI2.frame(parent, "ember", 10, 14.0, "orange", {"pattern_mix": 0.0})
	f.name = "PrizeCard"
	UI2.center(UI2.text(f, "THIS WEEK'S PRIZES", 15, Color("#ffd27a")))
	for t in Eco.LB_PRIZES:
		var r := UI.row(f, 6)
		var place := "#%d" % int(t.from) if int(t.from) == int(t.to) else "#%d-%d" % [int(t.from), int(t.to)]
		var pl := UI.label(r, place, 13, MEDAL[0] if int(t.from) == 1 else Color.WHITE, UI.HEAVY_FONT)
		pl.autowrap_mode = TextServer.AUTOWRAP_OFF
		pl.custom_minimum_size.x = 64
		var bits := ["%d gems" % int(t.gems)]
		if str(t.get("chest", "")) != "":
			bits.append(str(Eco.CHESTS[str(t.chest)].name))
		if str(t.get("title", "")) != "":
			bits.append("title \"%s\"" % str(NetT.TITLES[str(t.title)][0]))
		var bl := UI.label(r, " + ".join(bits), 12, Color.WHITE, UI.HEAVY_FONT)
		bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI2.center(UI2.body(f, "Play %d or more online matches in the week to be in the running." % Eco.LB_MIN_MATCHES, 11, Color(1, 1, 1, 0.8)))

static func _date(iso: String) -> String:
	# "2026-10-12" -> "OCT 12"
	var p := iso.split("-")
	if p.size() != 3:
		return iso
	var months := ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
	return "%s %d" % [months[clampi(int(p[1]) - 1, 0, 11)], int(p[2])]

static func _left(s: int) -> String:
	if s >= 86400:
		return "%dd %dh" % [s / 86400, (s % 86400) / 3600]
	if s >= 3600:
		return "%dh %dm" % [s / 3600, (s % 3600) / 60]
	return "%dm" % maxi(1, s / 60)
