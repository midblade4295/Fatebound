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
