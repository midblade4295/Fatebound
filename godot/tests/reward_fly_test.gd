extends SceneTree
# Currency flies into its counter (0.31.105, Kevin: "when a player obtains them it'll play a animation where they fly
# to the players total amount at top of screen" + "Yes put an ember counter at top also"):
#  - the top bar has gold and gems (0.31.105-0.31.183 Embers too: 0.31.184, two currencies); the gem counter opens the
#    shop;
#  - a gain starts a burst from the tap that claimed it; the counter keeps its old number until the pieces land, counts
#    up as they do, and ends on the profile's amount;
#  - spending shows at once; a restored save and a gain during a match don't fly (the match's gains fly on the way back);
#  - the new art: the Meshy coin / diamond / ember icons and their turning strips.
#   godot --headless --fixed-fps 30 --resolution 420x933 --path godot -s res://tests/reward_fly_test.gd
const App = preload("res://scripts/app/siege_app.gd")
const UI = preload("res://scripts/app/ui.gd")
const RewardFly = preload("res://scripts/app/reward_fly.gd")
var fails: Array = []
var app
var f := 0
var mark := 0

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	var base := "user://rewardfly-%d" % Time.get_ticks_usec()
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

func _txt(n: int) -> String:
	return UI.compact(n)

func _process(_d: float) -> bool:
	f += 1
	var p = app.profile
	if f == 6:
		var art := []
		for n in ["coin", "coins_s", "coins_m", "coins_l", "gem", "gems", "ember", "embers", "coin_spin", "gem_spin", "ember_spin"]:
			if not ResourceLoader.exists("res://assets/ui/currency/%s.png" % n):
				art.append(n)
		var strip: Texture2D = load("res://assets/ui/currency/coin_spin.png")
		check(art.is_empty() and strip != null and strip.get_width() == strip.get_height() * RewardFly.FRAMES, "the new currency art and its turning strips are there %s" % str(art))
		check(app.gold_label != null and app.gems_label != null and app.gems_label.is_visible_in_tree() and not ("embers_label" in app)
			and _btn("pill_ember") == null, "the top bar counts gold and gems -- no Embers (0.31.184)")
		app.quiet_top = true                       # some gems to spend
		p.d.gems = 60
		app.refresh_top()
		app.quiet_top = false
		# a gain: from the tap that claimed it, the counter waits for the pieces
		app._last_press = Vector2(210, 620)
		app._last_press_ms = Time.get_ticks_msec()
		check(app.fly_origin() == Vector2(210, 620), "a reward flies from the tap that claimed it")
		var before := int(p.d.gold)
		p.d.gold += 250
		app.refresh_top()
		check(app.reward_fly.bursts == 1 and app.reward_fly.flying == RewardFly.pieces_for(250) and app.gold_label.text == _txt(before),
			"250 gold: %d pieces in the air, the counter still at %s" % [app.reward_fly.flying, app.gold_label.text])
		# spending shows at once
		p.d.gems = int(p.d.gems) - 5
		app.refresh_top()
		check(app.gems_label.text == _txt(int(p.d.gems)) and app.reward_fly.bursts == 1, "spending gems shows at once, nothing flies")
		p.d.gems = int(p.d.gems) + 12
		app.refresh_top()
		check(app.reward_fly.bursts == 2, "12 gems fly too")
		mark = f
	if mark > 0 and f == mark + 34:
		var shown := int(app._cur.coin.shown)
		check(shown > int(p.d.gold) - 250 and shown < int(p.d.gold) and app.reward_fly.flying > 0,
			"the counter counts up as the pieces land (%d of %d)" % [shown, int(p.d.gold)])
	if mark > 0 and f == mark + 90:
		check(app.reward_fly.flying == 0 and app.gold_label.text == _txt(int(p.d.gold)) and app.gems_label.text == _txt(int(p.d.gems)),
			"all landed: the counters say %s gold, %s gems" % [app.gold_label.text, app.gems_label.text])
		# a restored save: no flight
		app.quiet_top = true
		p.d.gold += 1000
		app.rebuild()
		app.quiet_top = false
		check(app.reward_fly.bursts == 2 and app.gold_label.text == _txt(int(p.d.gold)), "a restored save just changes the counter")
		# during a match the counters wait, and fly on the way back
		app._set_menu_active(false)
		p.d.gold += 40
		app.refresh_top()
		check(app.reward_fly.bursts == 2 and app.gold_label.text == _txt(int(p.d.gold) - 40), "gold won in a match doesn't fly while it runs")
		app._set_menu_active(true)
		app.refresh_top()
		check(app.reward_fly.bursts == 3, "... it flies when the menus come back")
		# the gem counter opens the shop
		var b := _btn("pill_gem")
		if b != null:
			b.pressed.emit()
		check(b != null and app.tab == "shop", "the gem counter opens the shop")
		print("REWARD_FLY_PASS" if fails.is_empty() else "REWARD_FLY_FAIL %s" % str(fails))
		quit(0 if fails.is_empty() else 1)
	return false
