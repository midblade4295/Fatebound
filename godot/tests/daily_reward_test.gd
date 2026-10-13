extends SceneTree
# 0.31.119 (Kevin: "Do all" -- 6. a daily login reward).
#  1. the profile: one claim a UTC day, the calendar's next reward (150 gold, 25 Embers, a Silver chest, 250 gold,
#     50 Embers, 400 gold, a Gold chest + 20 gems), round and round; a missed day doesn't reset it; a chest waits when
#     the slots are full.
#  2. the server (server/eco_accounts.gd replaying the phone's ops with ITS clock): a claim counts once a day -- a phone
#     that changed its clock and claims again gets nothing.
#  3. the app: the card opens by itself on Home once a day (daily_auto), CLAIM pays and marks the day, it doesn't open
#     again that day; ORDERS has it at the top and counts it on its badge.
#   godot --headless --path godot -s res://tests/daily_reward_test.gd
const Profile = preload("res://scripts/meta/profile.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const Accounts = preload("res://server/eco_accounts.gd")
const App = preload("res://scripts/app/siege_app.gd")
const DailyReward = preload("res://scripts/app/daily_reward.gd")
const OrdersPanel = preload("res://scripts/app/orders_panel.gd")

const T0 := 1791806400                  # 2026-10-12 12:00 UTC

var fails: Array = []
var app
var frames := 0
var base := ""

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	_part1()
	_part2()
	base = "user://dailytest-%d" % Time.get_ticks_usec()
	var p = Profile.new(base + "-profile.json", base + "-none.json")
	p.load_or_create()
	p.d.tutorial_done = true
	p.save()
	app = App.new()
	app.profile_path = base + "-profile.json"
	app.legacy_path = base + "-none.json"
	app.daily_auto = true
	root.add_child(app)
	app.size = Vector2(420, 933)

func _part1() -> void:
	var p = Profile.new("user://dailytest-p1-%d.json" % Time.get_ticks_usec(), "user://none.json")
	p.load_or_create()
	p.now_override = T0
	var g0 := int(p.d.gold)
	check(p.login_ready() and p.login_next() == 0, "a new player: day 1 ready")
	var r: Dictionary = p.claim_login()
	check(bool(r.ok) and int(r.day) == 1 and int(p.d.gold) == g0 + 150 and not p.login_ready(), "day 1: +150 gold, done for today")
	check(not bool(p.claim_login().ok) and int(p.d.gold) == g0 + 150, "twice the same day: nothing")
	p.now_override = T0 + 11 * 3600 + 59 * 60                       # 23:59 UTC
	check(not p.login_ready(), "still today at 23:59 UTC")
	p.now_override = T0 + 12 * 3600 + 60                            # 00:01 UTC the next day
	var e0 := int(p.d.embers)
	check(p.login_ready() and bool(p.claim_login().ok) and int(p.d.embers) == e0 + 25, "day 2 (the next UTC day): +25 Embers")
	p.now_override += 4 * 86400                                       # 3 days missed
	var slots := (p.d.chests.slots as Array).size()
	r = p.claim_login()
	check(bool(r.ok) and int(r.day) == 3 and (p.d.chests.slots as Array).size() == slots + 1 and str(p.d.chests.slots[-1].kind) == "silver",
		"missed days don't reset it: day 3, a Silver chest")
	for i in 3:
		p.now_override += 86400
		p.claim_login()
	# slots full: the day-7 Gold chest waits
	while (p.d.chests.slots as Array).size() < Eco.CHEST_SLOTS:
		p.add_chest("wooden", {})
	var gems0 := int(p.d.gems)
	p.now_override += 86400
	r = p.claim_login()
	check(bool(r.ok) and int(r.day) == 7 and int(p.d.gems) == gems0 + 20 and (p.d.chests.queue as Array).has("gold") and bool(r.chests[0].get("queued", false)),
		"day 7: +20 gems and a Gold chest (waiting: the slots are full)")
	p.now_override += 86400
	var gg := int(p.d.gold)
	r = p.claim_login()
	check(bool(r.ok) and int(r.day) == 1 and int(p.d.gold) == gg + 150, "then round again: day 1")
	var week := {"gold":0, "gems":0, "embers":0}
	for rw in Eco.LOGIN_REWARDS:
		for k in week:
			week[k] += int(rw.get(k, 0))
	check(week.gold == 800 and week.gems == 20 and week.embers == 75, "a week: 800 gold, 75 Embers, 20 gems, a Silver and a Gold chest (%s)" % str(week))

func _part2() -> void:
	var tmp := OS.get_user_data_dir().path_join("dailytest-srv-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	var acc = Accounts.new(tmp)
	acc.now_override = T0
	var a: Dictionary = acc.handle({"t":"eco", "new":true})
	var id := str(a.acct)
	var key := str(a.key)
	var g0 := int(a.profile.gold)
	var r: Dictionary = acc.handle({"t":"eco", "acct":id, "key":key, "ops":[{"s":1, "op":"claim_login", "a":[]}]})
	check(bool(r.results[0].ok) and int(r.profile.gold) == g0 + 150, "the server replays the claim (+150 gold)")
	r = acc.handle({"t":"eco", "acct":id, "key":key, "ops":[{"s":2, "op":"claim_login", "a":[]}]})
	check(not bool(r.results[0].ok) and int(r.profile.gold) == g0 + 150, "a phone that moved its clock and claims again: the server says no")
	acc.now_override = T0 + 86400
	r = acc.handle({"t":"eco", "acct":id, "key":key, "ops":[{"s":3, "op":"claim_login", "a":[]}]})
	check(bool(r.results[0].ok) and int(r.profile.embers) >= 25, "the server's next day: day 2")

func _find(node: Node, pred: Callable) -> Array:
	var out := []
	if pred.call(node):
		out.append(node)
	for c in node.get_children():
		out.append_array(_find(c, pred))
	return out

func _btn(key: String) -> Button:
	var l := _find(app, func(n): return n is Button and str(n.get_meta("action_key", "")) == key and (n as Control).is_visible_in_tree())
	return l[0] if not l.is_empty() else null

func _process(_d: float) -> bool:
	frames += 1
	if frames == 20:
		check(app.modal is DailyReward, "Home: the daily reward opens by itself")
		var t1 := _find(app.modal, func(n): return str(n.name) == "DayTile1")
		check(not t1.is_empty() and bool(t1[0].get_meta("today")) and not bool(t1[0].get_meta("claimed")), "day 1 is today's")
		var ob := _btn("side_orders")
		notes_badge = ob != null
		var g0 := int(app.profile.d.gold)
		_btn("daily_claim").pressed.emit()
		check(int(app.profile.d.gold) == g0 + 150 and not app.profile.login_ready(), "CLAIM: +150 gold")
	elif frames == 24:
		var t1 := _find(app.modal, func(n): return str(n.name) == "DayTile1")
		check(not t1.is_empty() and bool(t1[0].get_meta("claimed")) and _btn("daily_claim") == null and _btn("daily_ok") != null, "day 1 claimed, CLAIM gone")
		_btn("daily_ok").pressed.emit()
	elif frames == 28:
		check(app.modal == null or not is_instance_valid(app.modal), "OK closes it")
		app.show_tab("home")
	elif frames == 36:
		check(app.modal == null or not is_instance_valid(app.modal), "it doesn't open again the same day")
		_btn("side_orders").pressed.emit()
	elif frames == 40:
		check(app.modal is OrdersPanel and not _find(app.modal, func(n): return str(n.name) == "DailyCard").is_empty() and _btn("orders_daily") != null,
			"ORDERS has the daily reward at the top")
		check(notes_badge, "ORDERS medallion on Home")
		print("DAILY_REWARD_PASS" if fails.is_empty() else "DAILY_REWARD_FAIL %s" % str(fails))
		quit(0 if fails.is_empty() else 1)
	return false

var notes_badge := false
