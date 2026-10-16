extends SceneTree
# 0.31.153 COMMANDER (the test) in the app:
#  1. the deck window (0.31.155: no longer on Home -- 5V5 has its place; app.open_commander());
#  2. the deck window: 14 cards, your 8 ticked, the average cost; a card out -> PICK 1 MORE (BATTLE off); a ninth
#     refused; back to 8 -> BATTLE; the deck kept on the phone;
#  3. BATTLE: an offline COMMANDER match with that deck (no server, no ticket); the hand drawn from it;
#  4. a card tapped on the HUD sends its squad; one you can't pay for: refused, said why;
#  5. the end: the cards each side played on the results, no rewards (the gold as it was).
#   godot --headless --path godot -s res://tests/commander_ui_test.gd   (SHOT_DIR=... under Xvfb for pictures)
const App = preload("res://scripts/app/siege_app.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const Cards = preload("res://scripts/meta/cards.gd")
const CmdPanel = preload("res://scripts/app/commander_panel.gd")

var fails: Array = []
var phase := "boot"
var t := 0.0
var t_phase := 0.0
var app
var shots := ""
var gold0 := 0

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func btn(key: String, node: Node = null) -> Button:
	if node == null:
		node = app
	if node is Button and str(node.get_meta("action_key", "")) == key and node.is_visible_in_tree():
		return node
	for c in node.get_children():
		var r := btn(key, c)
		if r != null:
			return r
	return null

func press(key: String) -> bool:
	var b := btn(key)
	if b == null or b.disabled:
		check(false, "button %s present and enabled" % key)
		return false
	b.pressed.emit()
	return true

func has_text(node: Node, s: String) -> bool:
	if (node is Label and (node as Label).text.contains(s)) or (node is Button and (node as Button).text.contains(s)):
		return node.is_visible_in_tree()
	for c in node.get_children():
		if has_text(c, s):
			return true
	return false

func _init() -> void:
	shots = OS.get_environment("SHOT_DIR") if DisplayServer.get_name() != "headless" else ""
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")

func _shot(name: String) -> void:
	if shots != "":
		root.get_viewport().get_texture().get_image().save_png(shots.path_join(name + ".png"))

func _go(next: String) -> void:
	phase = next
	t_phase = 0.0

func _process(delta: float) -> bool:
	t += delta
	t_phase += delta
	if t > 120.0:
		check(false, "timed out in phase %s" % phase)
		return _finish()
	match phase:
		"boot":
			var base := "user://cmdui-%d" % Time.get_ticks_usec()
			var p = Profile.new(base + "-profile.json", base + "-none.json")
			p.load_or_create()
			p.d.name = "Alice"
			p.d.tutorial_done = true
			p.save()
			app = App.new()
			app.profile_path = base + "-profile.json"
			app.legacy_path = base + "-none.json"
			root.add_child(app)
			_go("home")
		"home":
			if t_phase > 1.0:
				# (0.31.155: Home's medallion is 5V5's now -- moba_ui_test; COMMANDER opens from the app)
				app.open_commander()
				_go("deck")
		"deck":
			if t_phase > 0.4:
				check(app.modal is CmdPanel, "it opens the deck window")
				var m = app.modal
				var n := 0
				for id in Cards.ORDER:
					if btn("cmd_card_" + str(id)) != null:
						n += 1
				check(n == 14 and m.deck == Cards.DEFAULT_DECK and has_text(m, "8 / 8") and has_text(m, "average cost"), "14 cards; the starting deck of 8, its average cost")
				_shot("cmd_deck")
				press("cmd_card_knights")
				check(m.deck.size() == 7 and not m.deck.has("knights") and btn("cmd_battle").disabled and has_text(m, "PICK 1 MORE"),
					"Knights out: 7, PICK 1 MORE (BATTLE off)")
				check(has_text(m, "Knights (Common, 3 to play, 2 soldiers)"), "...the card described under the grid")
				press("cmd_card_archmage")
				press("cmd_card_peasants")
				check(m.deck.size() == 8 and m.deck.has("archmage") and not m.deck.has("peasants"), "the Archmage in; a ninth (Peasants) refused")
				check(not btn("cmd_battle").disabled and has_text(m, "BATTLE"), "8: BATTLE")
				gold0 = int(app.profile.d.gold)
				press("cmd_battle")
				_go("match")
		"match":
			if app.siege != null and app.siege.sim != null and app.siege.hud != null and t_phase > 1.0:
				var s = app.siege
				var deck: Array = app.profile.d.settings.get("cmd_deck", [])
				check(deck.has("archmage") and not deck.has("knights"), "the deck kept on the phone")
				check(s.commander and not s.online and not s.tutorial and s.sim.commander and s.sim.cmd_ready(0).size() == 15,
					"BATTLE: an offline COMMANDER match, our 15 in the barracks")
				var hand: Array = (s.sim.cmd[0].hand as Array) + (s.sim.cmd[0].queue as Array)
				check(hand.all(func(id): return deck.has(id)), "the hand is drawn from that deck")
				# a card we can pay for: put Archers in slot 0 with 5 points
				s.sim.cmd[0].hand[0] = "archers"
				s.sim.cmd[0].pts = 5.0
				var r: Rect2 = s.hud.card_rect(0)
				s.hud._touch(0, r.get_center(), true)
				s.hud._touch(0, r.get_center(), false)
				check(s.cards_played == 1 and s.sim.cmd_army(0) == 2 and is_equal_approx(float(s.sim.cmd[0].pts), 2.0), "Archers tapped: two soldiers out, 3 points spent")
				s.sim.cmd[0].hand[1] = "archmage"
				var r1: Rect2 = s.hud.card_rect(1)
				s.hud._touch(0, r1.get_center(), true)
				s.hud._touch(0, r1.get_center(), false)
				check(s.cards_played == 1 and s.hud._toast.contains("needs 5 command points"), "the Archmage with 2 points: refused (\"%s\")" % s.hud._toast)
				_go("play")
		"play":
			if t_phase > 2.5:
				_shot("cmd_match")
				var s = app.siege
				s.sim._finish("time")
				_go("end")
		"end":
			if t_phase > 1.5:
				var s = app.siege
				check(s.hud.result_panel != null and has_text(s.hud.result_panel, "Cards played: you 1") and has_text(s.hud.result_panel, "no rewards yet"),
					"the results: the cards played, no rewards")
				check(int(app.profile.d.gold) == gold0, "the gold as it was")
				_shot("cmd_result")
				return _finish()
	return false

func _finish() -> bool:
	print("COMMANDER_UI_PASS" if fails.is_empty() else "COMMANDER_UI_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
	return true
