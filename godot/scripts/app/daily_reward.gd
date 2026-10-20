extends Control
# 0.31.119 (Kevin: "Do all" -- 6. a daily login reward): the DAILY REWARD card. Seven days (Eco.LOGIN_REWARDS), one claim
# each UTC day, round and round -- a missed day doesn't reset it. It opens by itself on Home the first time each day a
# claim is waiting (siege_app.offer_daily), and from ORDERS. CLAIM is the profile's claim_login op: the phone shows it at
# once and the server replays it with its own clock (eco_sync), so a changed phone clock can't claim twice.
const UI = preload("res://scripts/app/ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")
const Eco = preload("res://scripts/meta/economy.gd")

var app
var _card: VBoxContainer

func open(a) -> void:
	app = a
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.06, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var holder := MarginContainer.new()
	holder.custom_minimum_size = Vector2(minf(392.0, app.size.x - 20.0), 0)
	center.add_child(holder)
	_card = UI2.frame(holder, "royal", 14, 22.0, "gold")
	_card.add_theme_constant_override("separation", 10)
	_render()

func refresh() -> void:
	_render()

static func reward_text(rw: Dictionary) -> Array:
	# -> [[icon path, "+150"], ...] for a day's tile
	var out := []
	if rw.has("gold"):
		out.append(["res://assets/ui/currency/coin.png", "%d" % int(rw.gold)])
	if rw.has("chest"):
		out.append([UI2.V2 + "chests/%s_icon.png" % str({"wooden": "wood"}.get(str(rw.chest), str(rw.chest))), str(Eco.CHESTS[str(rw.chest)].name)])
	if rw.has("gems"):
		out.append(["res://assets/ui/currency/gems.png", "%d" % int(rw.gems)])
	return out

func _render() -> void:
	for c in _card.get_children():
		_card.remove_child(c)
		c.queue_free()
	var p = app.profile
	var ready: bool = p.login_ready()
	var nxt: int = p.login_next()                       # the day the next claim gives (0-6)
	var today := nxt if ready else posmod(nxt - 1, 7)   # the day that's today's (claimed or not)
	var head := UI.row(_card, 8)
	UI2.img(head, UI2.V2 + "chests/gold_icon.png", 44.0).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tl := UI2.text(head, "DAILY REWARD", 26, UI2.GOLD)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var x := UI2.button(head, "✕", "ghost", func():
		app.sfx("menuClose")
		app.close_modal(), "daily_close", 18, 40.0, 12.0)
	x.custom_minimum_size.x = 44
	UI2.center(UI2.body(_card, "A reward every day you play -- the best on day 7.", 12, UI2.SOFT))
	# the seven days: four on top, three under (day 7 wide)
	for row_days in [[0, 1, 2, 3], [4, 5, 6]]:
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 6)
		r.alignment = BoxContainer.ALIGNMENT_CENTER
		_card.add_child(r)
		for i in row_days:
			_tile(r, i, i < today or (i == today and not ready), i == today and ready, i == 6)
	if ready:
		var b := UI2.button(_card, "CLAIM DAY %d" % (nxt + 1), "green", func(): _claim(), "daily_claim", 20, 54.0, 16.0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UI2.sweep(b)
	else:
		var left := 86400 - posmod(int(p.now()), 86400)
		UI2.center(UI2.text(_card, "CLAIMED TODAY", 18, UI2.GREEN))
		UI2.center(UI2.body(_card, "Day %d in %s" % [nxt + 1, _left(left)], 13, UI2.SOFT, false))
		var ok := UI2.button(_card, "OK", "blue", func():
			app.sfx("menuClose")
			app.close_modal(), "daily_ok", 18, 46.0, 14.0)
		ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI2.center(UI2.body(_card, "Missed a day? No problem -- you pick up where you left off.", 11, UI2.MUTED))

func _tile(parent: Node, i: int, claimed: bool, is_today: bool, wide: bool) -> void:
	var t := PanelContainer.new()
	t.name = "DayTile%d" % (i + 1)
	t.set_meta("claimed", claimed)
	t.set_meta("today", is_today)
	t.custom_minimum_size = Vector2(176 if wide else 84, 104)
	var st := StyleBoxFlat.new()
	st.bg_color = Color("#2a6b3a") if is_today else (Color(0.02, 0.04, 0.1, 0.75) if claimed else Color(0.08, 0.12, 0.28, 0.95))
	st.border_color = UI2.GOLD if is_today else (Color(1, 1, 1, 0.15) if claimed else Color("#4d6bd8"))
	st.set_border_width_all(3 if is_today else 2)
	st.set_corner_radius_all(12)
	st.content_margin_top = 4
	st.content_margin_bottom = 4
	t.add_theme_stylebox_override("panel", st)
	parent.add_child(t)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 1)
	t.add_child(v)
	UI2.center(UI2.text(v, "DAY %d" % (i + 1), 12, UI2.CYAN if is_today else Color.WHITE))
	var icons := HBoxContainer.new()
	icons.alignment = BoxContainer.ALIGNMENT_CENTER
	icons.add_theme_constant_override("separation", 2)
	v.add_child(icons)
	var amounts := []
	for it in reward_text(Eco.LOGIN_REWARDS[i]):
		var im := UI2.img(icons, str(it[0]), 44.0 if wide else 40.0)
		if is_today:
			UI2.bob(im, 3.0, 0.9)
		amounts.append(str(it[1]))
	UI2.center(UI2.body(v, " + ".join(amounts), 11, Color.WHITE, false))
	if claimed:
		t.modulate = Color(1, 1, 1, 0.55)
		var ck := Label.new()
		ck.text = "✔"
		ck.add_theme_font_size_override("font_size", 30)
		ck.add_theme_color_override("font_color", UI2.GREEN)
		ck.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		ck.add_theme_constant_override("outline_size", 6)
		ck.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ck.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		t.add_child(ck)
	if is_today:
		UI2.pulse(t, 0.03, 0.9)

func _claim() -> void:
	var r: Dictionary = app.profile.claim_login()
	if not bool(r.get("ok", false)):
		app.toast("Already claimed today", UI.MUTED)
		_render()
		return
	app.sfx("confirm")
	var chests: Array = r.get("chests", [])
	for ch in chests:
		if bool(ch.get("queued", false)):
			app.toast("Your chest slots are full -- the %s waits for a free one" % str(Eco.CHESTS[str(ch.kind)].name), UI.GOLD)
		elif bool(ch.get("full", false)):
			app.toast("Chest slots full -- turned into %d gold" % int(ch.gold), UI.GOLD)
	if app.get("analytics") != null:
		app.analytics.log_ev("daily_reward", {"day":int(r.day)})
	app.rebuild()                                        # (the counters fly up; Home's chests show a new one)
	_render()

static func _left(s: int) -> String:
	if s >= 3600:
		return "%dh %dm" % [s / 3600, (s % 3600) / 60]
	return "%dm" % maxi(1, s / 60)
