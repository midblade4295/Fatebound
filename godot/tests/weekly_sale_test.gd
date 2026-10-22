extends SceneTree
# 0.31.203 (Kevin: "For featured outfits, let's make them discounted. A new set of on sale skins will rotate once per
# week. Let's make the graphic of the features look very eye catching"):
#  1. the week's three featured outfits are its sale -- 50 %, 35 %, 25 % off in that order; nothing else is; a new three
#     each Monday 00:00 UTC; sale prices round to 5 gems / 500 gold;
#  2. what everything costs now (Eco.skin_offer): the sale's price on a sale outfit, the full price on the rest;
#  3. buying one (Profile.buy_outfit) takes the sale's price, gems or (the rare line) gold, sends "buy_sale" with the
#     week it saw, and the server replaying it lands on the same account; a full-price outfit still sends buy_skin;
#  4. the server honours last week's sale for a day after it ends (a buy still on its way), not after; an outfit that
#     wasn't in that week's sale, or one already owned, is refused; a bad op is refused before it runs;
#  5. the shop: the WEEKLY SALE ribbon, its starburst on the stage and the three picks, the sale's price on the buy
#     button, the full price struck through, the badge on the sale's cards in the grid; buying from the stage.
#   godot --headless --path godot -s res://tests/weekly_sale_test.gd
const Eco = preload("res://scripts/meta/economy.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const Screens = preload("res://scripts/app/screens.gd")
var fails: Array = []
const T := 1791000000            # a Saturday (the app shots' clock)

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func fresh(tag: String, now: int) -> Profile:
	var p := Profile.new("user://sale_%s_%d.json" % [tag, Time.get_ticks_usec()], "user://none_%d.json" % Time.get_ticks_usec())
	p.load_or_create()
	p.now_override = now
	return p

func _week_with(pred: Callable) -> int:
	# the first week from T's on whose sale holds an outfit that passes pred
	var w := Eco.week_index(T)
	for i in 60:
		for id in Eco.featured_outfits_week(w + i):
			if pred.call(str(id)):
				return w + i
	return -1

func _init() -> void:
	# ---- 1. the sale
	var w := Eco.week_index(T)
	var ws := Eco.week_start(T)
	var feat := Eco.featured_outfits(T)
	check(feat.size() == 3 and feat == Eco.featured_outfits_week(w) and feat[0] != feat[1] and feat[1] != feat[2] and feat[0] != feat[2],
		"three outfits on sale this week: %s" % [feat])
	check(Time.get_datetime_dict_from_unix_time(ws).weekday == Time.WEEKDAY_MONDAY and ws <= T and T < ws + 7 * 86400
		and Time.get_datetime_dict_from_unix_time(ws).hour == 0, "the week starts Monday 00:00 UTC")
	var offs := []
	for id in feat:
		offs.append(Eco.sale_off(str(id), T))
	check(offs == [50, 35, 25], "50, 35 and 25 %% off, in the week's order: %s" % [offs])
	var others := 0
	for id in Eco.SKINS:
		if not feat.has(id) and Eco.sale_off(str(id), T) != 0:
			others += 1
	check(others == 0, "nothing else is on sale")
	var next := Eco.featured_outfits(ws + 7 * 86400)
	check(Eco.featured_outfits(ws + 7 * 86400 - 1) == feat and next != feat and not next.has(feat[0]) and not next.has(feat[1]) and not next.has(feat[2]),
		"a new three at Monday midnight: %s" % [next])
	var seen := {}
	for i in 12:
		for id in Eco.featured_outfits_week(w + i):
			seen[id] = true
	check(seen.size() == Eco.SKINS.size(), "every outfit comes round in 12 weeks (%d of %d)" % [seen.size(), Eco.SKINS.size()])
	check(Eco.sale_price(750, 50, 5) == 375 and Eco.sale_price(750, 35, 5) == 490 and Eco.sale_price(750, 25, 5) == 565
		and Eco.sale_price(390, 50, 5) == 195 and Eco.sale_price(390, 35, 5) == 255 and Eco.sale_price(390, 25, 5) == 295
		and Eco.sale_price(40000, 50, 500) == 20000 and Eco.sale_price(40000, 35, 500) == 26000 and Eco.sale_price(40000, 25, 500) == 30000
		and Eco.sale_price(750, 0, 5) == 750, "sale prices: 375 / 490 / 565 for an epic, 195 / 255 / 295 a rare, 20K / 26K / 30K gold")

	# ---- 2. what things cost now
	var top := str(feat[0])
	var o := Eco.skin_offer(top, T)
	check(int(o.off) == 50 and int(o.gems) == int(Eco.SKINS[top].gems) / 2 and int(o.was_gems) == int(Eco.SKINS[top].gems) and int(o.week) == w,
		"the top pick: half its gems (%s)" % [o])
	var plain := ""
	for id in Eco.SKINS:
		if not feat.has(id):
			plain = str(id)
			break
	var po := Eco.skin_offer(plain, T)
	check(int(po.off) == 0 and int(po.gems) == int(Eco.SKINS[plain].gems) and int(po.gold) == int(Eco.SKINS[plain].get("gold", 0)),
		"an outfit not on sale: its full price")

	# ---- 3. buying on sale, and the server replaying it
	var p := fresh("buy", T)
	p.d.gems = 2000
	p.d.gold = 100000
	var ops := []
	p.on_op = func(op: String, args: Array): ops.append([op, args.duplicate()])
	var r := p.buy_outfit(top)
	check(bool(r.ok) and int(p.d.gems) == 2000 - int(o.gems) and p.owns_skin(top) and p.worn_skin(str(Eco.SKINS[top].hero)) == top,
		"bought at the sale's price: %d gems left" % int(p.d.gems))
	check(ops.size() == 1 and ops[0] == ["buy_sale", [top, w, false]], "the op the server gets: %s" % [ops])
	var srv := fresh("srv", T + 30)
	srv.d.gems = 2000
	srv.d.gold = 100000
	var sr := srv.apply_op("buy_sale", [top, float(w), false])        # (JSON numbers arrive as floats)
	check(bool(sr.ok) and int(srv.d.gems) == int(p.d.gems) and srv.owns_skin(top), "the server replaying it: the same account")
	check(not bool(srv.apply_op("buy_sale", [top, float(w), false]).ok), "twice: refused (already yours)")
	ops.clear()
	var r2 := p.buy_outfit(plain)
	check(bool(r2.ok) and ops.size() == 1 and str(ops[0][0]) == "buy_skin", "an outfit not on sale: buy_skin at its full price")
	# the rare line on sale, for gold
	var fw := _week_with(func(id): return int(Eco.SKINS[id].get("gold", 0)) > 0)
	var frost := ""
	for id in Eco.featured_outfits_week(fw):
		if int(Eco.SKINS[str(id)].get("gold", 0)) > 0:
			frost = str(id)
			break
	var ft := Eco.week_start(T) + (fw - w) * 7 * 86400 + 3600
	var fo := Eco.skin_offer(frost, ft)
	var pg := fresh("gold", ft)
	pg.d.gold = 50000
	var rg := pg.buy_outfit(frost, true)
	check(frost != "" and int(fo.off) > 0 and bool(rg.ok) and int(pg.d.gold) == 50000 - int(fo.gold) and int(fo.gold) < int(Eco.SKINS[frost].gold),
		"a Frostbound outfit on sale for gold: %s for %d gold (was %d)" % [frost, int(fo.gold), int(fo.was_gold)])

	# ---- 4. the sale's end, and what's refused
	var late := fresh("late", ws + 7 * 86400 + 3600)              # an hour into next week
	late.d.gems = 2000
	var lr := late.apply_op("buy_sale", [str(feat[1]), float(w), false])
	check(bool(lr.ok) and int(late.d.gems) == 2000 - int(Eco.skin_offer(str(feat[1]), T).gems), "last week's sale an hour after it ended: honoured (a buy on its way)")
	var later := fresh("later", ws + 7 * 86400 + Eco.SALE_GRACE + 60)
	later.d.gems = 2000
	var lr2 := later.apply_op("buy_sale", [str(feat[1]), float(w), false])
	check(not bool(lr2.ok) and str(lr2.error) == "That sale has ended" and int(later.d.gems) == 2000, "a day after it ended: refused, nothing taken")
	var early := fresh("early", T)
	early.d.gems = 2000
	check(not bool(early.apply_op("buy_sale", [str(feat[0]), float(w + 1), false]).ok), "next week's sale: refused")
	check(str(early.apply_op("buy_sale", [plain, float(w), false]).error) == "Not on sale" and int(early.d.gems) == 2000, "an outfit not in the sale: refused")
	check(str(early.apply_op("buy_sale", [str(feat[0]), float(w)]).error) == "bad args", "a bad op: refused before it runs")
	var poor := fresh("poor", T)
	poor.d.gems = int(o.gems) - 1
	check(str(poor.buy_outfit(top).error) == "Not enough gems" and not poor.owns_skin(top), "not enough gems: refused")
	check(Profile.OPS.has("buy_sale") and Profile.OPS.buy_sale == [TYPE_STRING, TYPE_INT, TYPE_BOOL], "buy_sale: an op the server replays")

	# ---- 5. the shop
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1/fatebound/siege/ws")   # nothing listens there
	var App = load("res://scripts/app/siege_app.gd")
	var app = App.new()
	var base := "user://sale-app-%d" % Time.get_ticks_usec()
	app.profile_path = base + "-profile.json"
	app.legacy_path = base + "-none.json"
	app.now_override = T
	root.add_child(app)
	await process_frame
	await process_frame
	app.profile.d.gems = 5000
	app.show_tab("shop")
	await process_frame
	await process_frame
	var texts := []
	for l in app.find_children("*", "Label", true, false):
		if (l as Label).is_visible_in_tree():
			texts.append((l as Label).text)
	check(texts.has("WEEKLY SALE") and texts.has("-50%") and texts.has("-35%") and texts.has("-25%"), "the ribbon, and the three picks' starbursts")
	var buy := _btn(app, "feat_buy")
	check(buy != null and buy.text == UI_grouped(int(o.gems)), "the stage's button: the sale's price (%s)" % (buy.text if buy != null else "none"))
	check(texts.has(UI_grouped(int(o.was_gems))), "the full price, struck through")
	var card := _btn(app, "skin_buy_" + top)
	check(card != null and card.text == str(int(o.gems)), "its card in the grid: the sale's price too")
	var before := int(app.profile.d.gems)
	buy.pressed.emit()
	await process_frame
	var yes := _btn(app, "modal_yes")
	check(yes != null, "it asks first")
	if yes != null:
		yes.pressed.emit()
	await process_frame
	check(app.profile.owns_skin(top) and int(app.profile.d.gems) == before - int(o.gems), "bought from the stage at %d gems" % int(o.gems))
	print("WEEKLY_SALE_PASS" if fails.is_empty() else "WEEKLY_SALE_FAIL " + str(fails))
	quit(0 if fails.is_empty() else 1)

func UI_grouped(n: int) -> String:
	var UI = load("res://scripts/app/ui.gd")
	return UI.grouped(n)

func _btn(app, key: String) -> Button:
	for c in app.find_children("*", "Button", true, false):
		if str(c.get_meta("action_key", "")) == key and (c as Control).is_visible_in_tree():
			return c
	return null
