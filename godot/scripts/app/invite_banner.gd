extends PanelContainer
# 0.31.111 (Kevin: "They can then group up and form a party"): a party invite drops in under the top bar -- who, JOIN
# and ✕ -- for as long as it lasts (social.gd INVITE_LIFE), then slides away.
const UI = preload("res://scripts/app/ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")

var app
var party := ""
var _until := 0.0

func show_invite(a, pa: String, card: Dictionary, top: float) -> void:
	app = a
	party = pa
	_until = Time.get_ticks_msec() / 1000.0 + 30.0
	_frame(Color("#f7cd55"), top)
	var r := UI.row(self, 8)
	UI2.icon(r, "friends", 40.0).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(v)
	var n := UI2.text(v, str(card.get("n", "A friend")), 16, UI2.GOLD)
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UI2.body(v, "invited you to their party", 12, Color.WHITE, false)
	var j := UI2.button(r, "JOIN", "green", func():
		app.sfx("confirm")
		if not app.social.join(party):
			app.toast("Not connected to the server right now", UI.RED)
		queue_free(), "invite_banner_join", 15, 40.0, 12.0)
	j.custom_minimum_size.x = 76
	j.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var x := UI2.button(r, "✕", "ghost", func():
		app.sfx("menuClose")
		app.social.no_join(party)
		queue_free(), "invite_banner_no", 15, 40.0, 12.0)
	x.custom_minimum_size.x = 44
	x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_drop_in(top)

func _frame(border: Color, top: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.2, 0.96)
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 8
	add_theme_stylebox_override("panel", sb)
	anchor_left = 0.0
	anchor_right = 1.0
	offset_left = 10
	offset_right = -10
	offset_top = top

func _drop_in(top: float) -> void:
	modulate.a = 0.0
	position.y = top - 20.0
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "modulate:a", 1.0, 0.2)
	tw.tween_property(self, "position:y", top, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() / 1000.0 > _until or (app != null and party != "" and not app.social.invites.has(party)) \
			or (app != null and app.siege != null):
		set_process(false)
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.25)
		tw.tween_callback(queue_free)
