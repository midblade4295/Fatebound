extends Control
# 0.31.112 (Kevin: "for home screen I don't want it to scroll down, just have the chests at bottom and move the orders and
# stuff to its own popup menu"): the ORDERS window from Home's ORDERS medallion -- the daily and weekly orders (CLAIM,
# reroll), the Siege Pass summary and what's inside each chest. Redrawn after every claim (siege_app.rebuild calls
# refresh), keeping its scroll.
const UI = preload("res://scripts/app/ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const SocialUI = preload("res://scripts/app/social_ui.gd")
const Screens = preload("res://scripts/app/screens.gd")
const DailyReward = preload("res://scripts/app/daily_reward.gd")

var app
var _list: VBoxContainer
var _scroll: ScrollContainer

func open(a) -> void:
	app = a
	var w := SocialUI.window(self, "ORDERS", "scroll", func():
		app.sfx("menuClose")
		app.close_modal(), 56.0 + float(app.safe_top), 24.0)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.scroll_deadzone = 1000000                 # (drag-scrolled by the app, like the menus)
	(w.body as VBoxContainer).add_child(_scroll)
	set_meta("drag_scroll", _scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 12)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	_render()

func refresh() -> void:
	var keep := _scroll.scroll_vertical
	_render()
	_scroll.set_deferred("scroll_vertical", keep)

func _render() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_daily_card(_list)
	Screens.challenges_card(app, _list, "daily")
	Screens.challenges_card(app, _list, "weekly")
	Screens.pass_card(app, _list)
	# what's inside the chests (was a button on Home)
	var f := UI2.frame(_list, "night", 12, 16.0, "gold")
	f.add_theme_constant_override("separation", 6)
	UI2.text(f, "WHAT'S INSIDE THE CHESTS", 17, UI2.GOLD)
	for k in ["wooden", "silver", "gold", "royal"]:
		var r := UI.row(f, 8)
		var n := UI2.text(r, str(Eco.CHESTS[k].name).to_upper(), 13, Color.WHITE)
		n.custom_minimum_size.x = 104
		n.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var b := UI2.body(r, "%s to unlock  ·  %s" % [UI.duration(int(Eco.CHESTS[k].unlock)), Eco.chest_odds(k)], 11, UI2.SOFT)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _daily_card(parent: Node) -> void:
	# 0.31.119: the daily login reward -- today's (CLAIM) or when the next one is ready; the card opens the calendar
	var p = app.profile
	var ready: bool = p.login_ready()
	var nxt: int = p.login_next()
	var f := UI2.frame(parent, "ember" if ready else "night", 10, 16.0, "orange" if ready else "gold", {"pattern_mix": 0.0})
	f.name = "DailyCard"
	var r := UI.row(f, 10)
	UI2.img(r, UI2.V2 + "chests/gold_icon.png", 46.0).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(col)
	UI2.text(col, "DAILY REWARD", 17, UI2.GOLD)
	var parts := []
	for it in DailyReward.reward_text(Eco.LOGIN_REWARDS[nxt]):
		parts.append(str(it[1]))
	UI2.body(col, ("Day %d of 7 ready: %s" % [nxt + 1, " + ".join(parts)]) if ready else "Claimed today -- day %d tomorrow" % (nxt + 1), 12, Color.WHITE)
	var b := UI2.button(r, "CLAIM" if ready else "VIEW", "green" if ready else "blue", func():
		app.sfx("menuOpen")
		app.open_daily(), "orders_daily", 15, 40.0, 12.0)
	b.custom_minimum_size.x = 86
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if ready:
		UI2.sweep(b)
