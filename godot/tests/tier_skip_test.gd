extends SceneTree
# Siege Pass tier skips (0.31.107, Kevin: "Can you put tier skips for the battlepass. Players can buy 10 tiers for
# gems"): 10 tiers for 1000 gems, keeping the progress into the current tier; their rewards then wait to be claimed;
# near the end only what's left (and its price); none when complete or without the gems; never a way to make gems;
# and on the pass screen through its button and the confirm.
#   godot --headless --resolution 420x933 --path godot -s res://tests/tier_skip_test.gd
const App = preload("res://scripts/app/siege_app.gd")
const Eco = preload("res://scripts/meta/economy.gd")
var fails: Array = []
var app
var f := 0

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	var base := "user://tierskip-%d" % Time.get_ticks_usec()
	app = App.new()
	app.profile_path = base + "-profile.json"
	app.legacy_path = base + "-none.json"
	app.now_override = 1791000000
	root.add_child(app)

func _btn(key: String) -> BaseButton:
	for c in app.find_children("*", "BaseButton", true, false):
		if str(c.get_meta("action_key", "")) == key and (c as Control).is_visible_in_tree():
			return c
	return null

func _process(_d: float) -> bool:
	f += 1
	var p = app.profile
	if f == 5:
		# never a way to make gems: any 10 tiers give back far less than they cost
		var worst := 0
		for sid in range(1, 7):
			for s in range(0, Eco.PASS_TIERS - Eco.TIER_SKIP + 1):
				var g := 0
				for t in range(s + 1, s + Eco.TIER_SKIP + 1):
					g += int(Eco.pass_reward(sid, t, false).get("gems", 0)) + int(Eco.pass_reward(sid, t, true).get("gems", 0))
				worst = maxi(worst, g)
		check(worst < Eco.TIER_SKIP * Eco.TIER_SKIP_GEMS / 2, "10 tiers give back at most %d gems of the %d they cost" % [worst, Eco.TIER_SKIP * Eco.TIER_SKIP_GEMS])
		# 10 tiers for 1000 gems, the progress kept
		p.d.pass.xp = 3 * Eco.TIER_XP + 900
		p.d.gems = 1500
		var o: Dictionary = p.skip_offer()
		check(int(o.tiers) == 10 and int(o.gems) == 1000, "the offer: 10 tiers for 1000 gems")
		var r: Dictionary = p.skip_tiers()
		check(r.ok and p.pass_tier() == 13 and int(p.d.pass.xp) == 13 * Eco.TIER_XP + 900 and int(p.d.gems) == 500 and (r.tiers as Array).size() == 10,
			"skipped: tier %d, %d XP into it, %d gems left" % [p.pass_tier(), int(p.d.pass.xp) - p.pass_tier() * Eco.TIER_XP, int(p.d.gems)])
		check(p.can_claim(13, false) and p.can_claim(4, false), "the skipped tiers' rewards wait to be claimed")
		check(not p.skip_tiers().ok and int(p.d.gems) == 500, "without the gems: nothing happens")
		# near the end: only what's left
		p.d.pass.xp = 26 * Eco.TIER_XP + 100
		p.d.gems = 5000
		o = p.skip_offer()
		check(int(o.tiers) == 4 and int(o.gems) == 400, "at tier 26: the last 4 tiers for 400 gems")
		r = p.skip_tiers()
		check(r.ok and p.pass_tier() == Eco.PASS_TIERS and int(p.d.gems) == 4600, "... to tier 30")
		check(int(p.skip_offer().tiers) == 0 and not p.skip_tiers().ok and int(p.d.gems) == 4600, "a complete pass sells no skips")
		# on the pass screen: the button, the confirm, the tier
		p.d.pass.xp = 2 * Eco.TIER_XP
		p.save()
		app.show_tab("pass")
	if f == 10:
		var b := _btn("skip_tiers")
		check(b != null and not b.disabled, "the pass screen offers the skip")
		if b != null:
			b.pressed.emit()
	if f == 14:
		var yes := _btn("modal_yes")
		check(yes != null, "it asks first")
		if yes != null:
			yes.pressed.emit()
	if f == 20:
		check(p.pass_tier() == 12 and int(p.d.gems) == 3600, "confirmed: tier %d, %d gems" % [p.pass_tier(), int(p.d.gems)])
		print("TIER_SKIP_PASS" if fails.is_empty() else "TIER_SKIP_FAIL %s" % str(fails))
		quit(0 if fails.is_empty() else 1)
	return false
