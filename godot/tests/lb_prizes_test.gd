extends SceneTree
# 0.31.120 (Kevin: prizes for the weekly leaderboard).
#  1. server/leaderboard.gd: only players with Eco.LB_MIN_MATCHES matches rank for a prize (they're listed first); when
#     the week ends the server pays #1 / #2-3 / #4-10 / #11-100 (Eco.LB_PRIZES); a week is paid once, even after a
#     restart
#  2. Profile.grant_prize / eco_accounts.grant_prize: gems, a reward chest, the prize title; a second prize for the
#     same week is refused
#  3. the app: the prize says so on Home once; the leaderboard window lists the prizes; the Locker has the prize titles
#   godot --headless --path godot -s res://tests/lb_prizes_test.gd
const Leaderboard = preload("res://server/leaderboard.gd")
const Accounts = preload("res://server/eco_accounts.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const App = preload("res://scripts/app/siege_app.gd")

const MON := 1791763200                 # 2026-10-12 00:00 UTC, a Monday

var fails: Array = []
var app
var frames := 0

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	# --- 1. the board
	var dir := OS.get_user_data_dir().path_join("lbprize-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(dir)
	var paid := []
	var lb = Leaderboard.new(dir, MON + 3600)
	lb.pay_fn = func(acct, week, rank, prize): paid.append([acct, week, rank, prize]); return true
	lb.start()
	for i in 12:
		var a := "%020x" % (i + 1)
		for m in 3:
			lb.add_match(a, "P%d" % i, "", {"kills":i * 2}, i % 2 == 0)
	lb.add_match("f".repeat(20), "OneMatchWonder", "", {"rescues":5, "kills":40}, true)      # 1,400 points, 1 match
	var ans: Dictionary = lb.answer("f".repeat(20), [])
	check(str(ans.top[0].name) != "OneMatchWonder" and int(ans.me.rank) == 13 and not bool(ans.me.q) and bool(ans.top[0].q),
		"a player with too few matches ranks after those who can win (rank %d)" % int(ans.me.rank))
	lb.now_override = MON + 7 * 86400 + 30
	lb.answer("x", [])
	check(paid.size() == 12 and int(paid[0][2]) == 1 and str(paid[0][1]) == "2026-10-12" and str(paid[0][3].get("title", "")) == "title_champion"
		and str(paid[1][3].get("title", "")) == "title_contender" and str(paid[3][3].get("title", "")) == "title_top_ten"
		and str(paid[10][3].get("chest", "")) == "silver" and not paid.any(func(x): return x[0] == "f".repeat(20)),
		"the week ends: #1 Champion, #2-3 Contender, #4-10 of the Ten, #11+ a Silver chest; the 1-match player nothing (%d paid)" % paid.size())
	var lb2 = Leaderboard.new(dir, MON + 7 * 86400 + 90)
	var paid2 := []
	lb2.pay_fn = func(acct, week, rank, prize): paid2.append(acct); return true
	lb2.start()
	check(paid2.is_empty() and lb2.paid == "2026-10-12", "after a restart the week isn't paid again")
	# --- 2. the account
	var p = Profile.new("user://lbprize-p-%d.json" % Time.get_ticks_usec(), "user://none.json")
	p.load_or_create()
	var g0 := int(p.d.gems)
	var r: Dictionary = p.grant_prize("2026-10-12", 2, Eco.lb_prize(2))
	check(bool(r.ok) and int(p.d.gems) == g0 + 200 and p.owns("title_contender") and str(p.d.chests.slots[-1].kind) == "gold" and int(p.d.prizes[0].rank) == 2,
		"a prize: 200 gems, a Gold chest, the Contender title")
	check(not bool(p.grant_prize("2026-10-12", 1, Eco.lb_prize(1)).ok) and int(p.d.gems) == g0 + 200, "a second prize for the same week: refused")
	check(not Profile.OPS.has("grant_prize"), "not an op a phone can send")
	var tmp := OS.get_user_data_dir().path_join("lbprize-srv-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	var acc = Accounts.new(tmp)
	var a: Dictionary = acc.handle({"t":"eco", "new":true})
	check(acc.grant_prize(str(a.acct), "2026-10-12", 1, Eco.lb_prize(1)) and not acc.grant_prize(str(a.acct), "2026-10-12", 1, Eco.lb_prize(1)),
		"the server pays the account once")
	var back: Dictionary = acc.handle({"t":"eco", "acct":str(a.acct), "key":str(a.key), "ops":[]})
	check((back.profile.owned as Array).has("title_champion") and int(back.profile.gems) >= 300, "...and the phone gets it with its account")
	# --- 3. the app
	var base := "user://lbprize-app-%d" % Time.get_ticks_usec()
	var ap = Profile.new(base + "-profile.json", base + "-none.json")
	ap.load_or_create()
	ap.d.tutorial_done = true
	ap.grant_prize("2026-10-12", 3, Eco.lb_prize(3))
	ap.save()
	app = App.new()
	app.profile_path = base + "-profile.json"
	app.legacy_path = base + "-none.json"
	app.daily_auto = true
	root.add_child(app)

func _labels(n: Node) -> Array:
	return n.find_children("*", "Label", true, false).map(func(l): return str((l as Label).text))

func _process(_d: float) -> bool:
	frames += 1
	if frames == 20:
		var txt := _labels(app.modal) if app.modal != null and is_instance_valid(app.modal) else []
		check(txt.has("LEADERBOARD PRIZE") and txt.any(func(t): return t.contains("#3") and t.contains("200 gems") and t.contains("the Contender")),
			"Home says so once: %s" % str(txt.slice(0, 3)))
		app.close_modal()
		app.show_tab("home")
	elif frames == 26:
		check(app.modal == null or not is_instance_valid(app.modal) or not _labels(app.modal).has("LEADERBOARD PRIZE"), "...not twice")
		app.close_modal()
		app.locker_class = "titles"
		app.show_tab("locker")
	elif frames == 32:
		var txt := _labels(app)
		check(txt.has("LEADERBOARD") and txt.has("Finish #1 on a weekly leaderboard") and txt.has("Finish 2nd or 3rd on a weekly leaderboard"),
			"the Locker lists the leaderboard's titles")
		print("LB_PRIZES_PASS" if fails.is_empty() else "LB_PRIZES_FAIL %s" % str(fails))
		quit(0 if fails.is_empty() else 1)
	return false
