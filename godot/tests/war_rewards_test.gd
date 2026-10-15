extends SceneTree
# 0.31.151 (Kevin: "Do them all" -- rewards for the war). The pieces under server/world.gd's rewards (world_test has
# who gets them: the fighters of the battle that takes a land, everyone in a clan of the house that wins the week):
#  1. Profile.grant_war: the reward into the profile (gold, gems, a reward chest), once per reward id, newest first;
#     not an op a phone can send;
#  2. eco_accounts.grant_war: the server pays the account once, and the phone gets it with its account;
#  3. the app: Home says so once (CROWN WAR: the text and what came with it).
#   godot --headless --path godot -s res://tests/war_rewards_test.gd
const Profile = preload("res://scripts/meta/profile.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const Accounts = preload("res://server/eco_accounts.gd")
const App = preload("res://scripts/app/siege_app.gd")

var fails: Array = []
var app
var t := 0.0
var step := 0

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")
	# --- 1. the profile
	var p = Profile.new("user://warrw-p-%d.json" % Time.get_ticks_usec(), "user://none.json")
	p.load_or_create()
	var g0 := int(p.d.gold)
	var n0 := (p.d.chests.slots as Array).size()
	var r: Dictionary = p.grant_war("take:mill:b1", "take", Eco.WAR_TAKE, "You took The Mill for House Lions!")
	check(bool(r.ok) and int(p.d.gold) == g0 + int(Eco.WAR_TAKE.gold) and (p.d.chests.slots as Array).size() == n0 + 1
		and str(p.d.chests.slots[-1].kind) == str(Eco.WAR_TAKE.chest) and str(p.d.war_rewards[0].id) == "take:mill:b1",
		"a land taken: +%d gold and a %s chest" % [int(Eco.WAR_TAKE.gold), str(Eco.WAR_TAKE.chest)])
	check(not bool(p.grant_war("take:mill:b1", "take", Eco.WAR_TAKE, "again").ok) and int(p.d.gold) == g0 + int(Eco.WAR_TAKE.gold), "the same reward twice: refused")
	var gm0 := int(p.d.gems)
	check(bool(p.grant_war("week:2026-10-12", "week", Eco.WAR_WEEK, "House Lions won the war this week!").ok) and int(p.d.gems) == gm0 + int(Eco.WAR_WEEK.gems)
		and str(p.d.war_rewards[0].id) == "week:2026-10-12" and (p.d.war_rewards as Array).size() == 2, "the week won: +%d gems and a Gold chest, newest first" % int(Eco.WAR_WEEK.gems))
	check(not Profile.OPS.has("grant_war"), "not an op a phone can send")
	# --- 2. the account
	var tmp := OS.get_user_data_dir().path_join("warrw-srv-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	var acc = Accounts.new(tmp)
	var a: Dictionary = acc.handle({"t":"eco", "new":true})
	check(acc.grant_war(str(a.acct), "week:2026-10-12", "week", Eco.WAR_WEEK, "House Lions won the war this week!")
		and not acc.grant_war(str(a.acct), "week:2026-10-12", "week", Eco.WAR_WEEK, "x"), "the server pays the account once")
	var back: Dictionary = acc.handle({"t":"eco", "acct":str(a.acct), "key":str(a.key), "ops":[]})
	check((back.profile.get("war_rewards", []) as Array).size() == 1 and int(back.profile.gems) >= int(Eco.WAR_WEEK.gems), "...and the phone gets it with its account")

func _process(d: float) -> bool:
	t += d
	match step:
		0:
			# --- 3. the app: Home says so, once
			var base := "user://warrw-app-%d" % Time.get_ticks_usec()
			var ap = Profile.new(base + "-profile.json", base + "-none.json")
			ap.load_or_create()
			ap.d.tutorial_done = true
			ap.d.settings["war_tour"] = true
			ap.grant_war("take:tower:b7", "take", Eco.WAR_TAKE, "You took Old Tower for House Stags!")
			ap.save()
			app = App.new()
			app.profile_path = base + "-profile.json"
			app.legacy_path = base + "-none.json"
			app.daily_auto = true
			root.add_child(app)
			step = 1
			t = 0.0
		1:
			if t > 1.0:
				# (Home up: the app says so by itself -- offer_daily -> offer_war_reward)
				check(is_instance_valid(app.modal) and _has(app.modal, "CROWN WAR") and _has(app.modal, "You took Old Tower for House Stags!")
					and _has(app.modal, "200 gold and a Silver Chest"), "Home: CROWN WAR -- \"You took Old Tower for House Stags! You got 200 gold and a Silver Chest.\"")
				app.close_modal()
				check(not app.offer_war_reward(), "...once")
				print("WAR_REWARDS_PASS" if fails.is_empty() else "WAR_REWARDS_FAIL %s" % str(fails))
				quit(0 if fails.is_empty() else 1)
	return false

func _has(node: Node, s: String) -> bool:
	if (node is Label and (node as Label).text.contains(s)) or (node is Button and (node as Button).text.contains(s)):
		return true
	for c in node.get_children():
		if _has(c, s):
			return true
	return false
