extends SceneTree
# 0.31.178 (Kevin: "Clean up and make this UI much better looking. Player health bar doesn't need to be there since they
# already have one above head. The objective doesn't need to be there ect. Make the other stuff prettier"): the 5v5's
# top (siege_hud.gd _draw_top).
#  - no health bar, class line or objective: the top isn't drawn again when your health changes (it's not on it);
#  - the bar: each side's King, towers standing and knockouts, as the sim has them; the clock on its plate;
#  - your level on a medallion ringed by your XP; the gold-and-shop button beside it (tapped: the shop); six item
#    slots under them; nothing of it under the horn and pause buttons, the kill feed or the quick chat;
#  - your King open with an enemy at him: the alert; not while his towers stand.
#   godot --headless --path godot -s res://tests/hud_top_test.gd
const Mode = preload("res://scripts/siege/siege_mode.gd")
var mode
var frames := 0
var fails := []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")
	mode = Mode.new()
	mode.moba_hero = "ranger"
	mode.match_seed = 4409
	root.add_child(mode)

func _process(_d: float) -> bool:
	frames += 1
	if mode.sim == null or not mode._build_queue.is_empty() or frames < 30:
		return false
	var s = mode.sim
	var hud = mode.hud
	var me: Dictionary = s.by_id["you"]
	var t := int(me.team)
	# no health on the top
	var k0: Array = hud._top_key(me)
	me.hp = float(me.max_hp) * 0.3
	check(hud._top_key(me) == k0, "your health isn't on the top (it's over your head)")
	me.hp = float(me.max_hp)
	# the bar as the sim has it
	var tw_dead: Dictionary = {}
	for tw in s.moba.towers:
		if int(tw.team) == 1 - t and int(tw.tier) == 1:
			tw.dead = true
			tw_dead = tw
			break
	s.kills[t] = 7
	var n_them := 0
	for tw in s.moba.towers:
		if int(tw.team) == 1 - t and not bool(tw.dead):
			n_them += 1
	check(hud.towers_standing(1 - t) == n_them and n_them == 10 and hud.towers_standing(t) == 11, "towers standing: %d of theirs, %d of yours" % [hud.towers_standing(1 - t), hud.towers_standing(t)])
	var k1: Array = hud._top_key(me)
	check(k1 != k0 and k1.has(7), "a knockout and a tower down redraw the bar")
	# level and XP
	me.level = 3
	me.xp = float(s.moba.need(3)) * 0.5
	check(absf(hud.xp_frac(me) - 0.5) < 0.01, "XP ring half way (%.2f)" % hud.xp_frac(me))
	me.level = s.moba.LEVEL_MAX
	check(hud.xp_frac(me) == 1.0, "at the top level: a full ring")
	# the layout: nothing in another's way
	var bar: Rect2 = hud.score_bar_rect()
	var shop: Rect2 = hud.shop_rect()
	var med := Rect2(hud.level_center() - Vector2(27, 27), Vector2(54, 54))
	var slots := Rect2(hud.item_slot_rect(0).position, hud.item_slot_rect(5).end - hud.item_slot_rect(0).position)
	var btns: Rect2 = hud.qc_btn.get_rect().merge(hud.pause_btn.get_rect())
	var clean := true
	for a in [bar, shop, med, slots, btns]:
		for b in [bar, shop, med, slots, btns]:
			if a != b and a.intersects(b):
				clean = false
	check(clean and slots.end.y + 30.0 < hud.KF_TOP and slots.end.x < hud.size.x * 0.5 and hud.clock_rect().position.y < bar.position.y,
		"bar, medallion, shop, slots and the buttons apart; all above the kill feed (slots end %.0f)" % slots.end.y)
	hud._touch(0, shop.get_center(), true)
	hud._touch(0, shop.get_center(), false)
	check(hud.shop_open(), "the gold button tapped: the shop")
	hud.close_shop()
	# the King alert
	var foe: Dictionary = {}
	for u in s.units:
		if int(u.team) == 1 - t and bool(u.get("hero", false)):
			foe = u
			break
	foe.pos = s.moba.king_pos(t) + Vector2(2, 0)
	s.step()                                                  # (who's near whom: the sim's grid, kept as it steps)
	check(not hud.king_alert(me), "an enemy at your King, his towers standing: no alert")
	for tw in s.moba.towers:
		if int(tw.team) == t and int(tw.tier) == 4:
			tw.dead = true
	foe.pos = s.moba.king_pos(t) + Vector2(2, 0)
	s.step()
	check(hud.king_alert(me), "his towers down: KING UNDER ATTACK")
	foe.pos = Vector2(0, 0)
	s.step()
	check(not hud.king_alert(me), "...and gone when the enemy is")
	print("HUD_TOP_%s" % ("PASS" if fails.is_empty() else "FAIL %s" % str(fails)))
	quit(0 if fails.is_empty() else 1)
	return true
