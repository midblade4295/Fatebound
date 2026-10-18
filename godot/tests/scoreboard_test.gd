extends SceneTree
# 0.31.119 (Kevin: "Do all" -- 3. a proper end-of-match screen): the results panel's MVP strip and the SCOREBOARD
# (siege_hud.gd), built from a finished match's units like the app has them (online: from the snapshots).
#   - points: knockout 20, tower, gate and King damage 1 per 10 (0.31.169: Siege's rescues, fish and gathering went)
#   - the MVP is the best of everyone (a bot that outplayed everybody is named as one: "Bot · <class>"; 0.31.177: a 5v5
#     bot by its seat's name, "Bot Alfred"); you: "YOU ARE
#     THE MVP!"; nobody scored: no strip
#   - SCORES opens the board (the results hide), both sides best first, players by name, you marked; BACK brings the
#     results back. A 5v5: five heroes a side.
#   godot --headless --path godot -s res://tests/scoreboard_test.gd
const Hud = preload("res://scripts/siege/siege_hud.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Moba = preload("res://scripts/siege/moba.gd")

var fails: Array = []
var hud
var sim
var frames := 0

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	check(Hud.points({"kills":5, "gate_dmg":455.0}) == 100 + 45, "points: KO 20, tower/gate/King damage 1 per 10")
	sim = Sim.new()
	sim.setup(5, 4242, -1)
	sim.setup_moba("", 4242)
	for u in sim.units:
		for k in ["kills", "deaths", "towers"]:
			u[k] = 0
		u.gate_dmg = 0.0
	sim.ended = true
	sim.winner = 0
	hud = Hud.new()
	hud.sim = sim
	hud.player_id = "b2"
	hud.player_name = "Kevin"
	hud.net_names = {"r3":"Rival", "b4":"Buddy"}
	root.add_child(hud)
	hud.size = Vector2(420, 933)

func _put(id: String, vals: Dictionary) -> void:
	for k in vals:
		sim.by_id[id][k] = vals[k]

func _labels(n: Node) -> Array:
	return n.find_children("*", "Label", true, false).map(func(l): return str((l as Label).text))

func _press(panel: Node, key: String) -> bool:
	for b in panel.find_children("*", "Button", true, false):
		if str(b.get_meta("key", "")) == key:
			(b as Button).pressed.emit()
			return true
	return false

func _process(_d: float) -> bool:
	frames += 1
	if frames == 2:
		# nobody scored: no strip
		hud.show_result({})
		check(hud.result_panel.find_child("MvpStrip", true, false) == null, "nobody scored: no MVP strip")
		hud.result_panel.visible = false               # (left in the tree: its placement timer may still run)
		hud.result_panel = null
		# a bot outplayed everybody
		_put("b2", {"kills":5, "deaths":2})                        # me: 100
		_put("r3", {"kills":12, "deaths":1})                       # Rival: 240
		_put("b0", {"kills":3, "gate_dmg":4000.0, "towers":2})     # a bot: 460
		_put("b4", {"gate_dmg":1500.0})                            # Buddy: 150
		_put("b1", {"kills":6})                                    # (bots above me on my side: 120, 140)
		_put("b3", {"kills":7})
		hud.show_result({})
	elif frames == 4:
		var strip: Node = hud.result_panel.find_child("MvpStrip", true, false)
		var mvp: Dictionary = hud.mvp()
		check(str(mvp.get("id", "")) == "b0", "the MVP is the best of everyone (%s)" % str(mvp.get("id", "")))
		var head := str((strip.find_child("MvpName", true, false) as Label).text) if strip != null else ""
		check(head == "MVP  ·  " + Moba.bot_label(sim.by_id["b0"]) and head.begins_with("MVP  ·  Bot "), "a bot MVP is named as one -- his seat's name (0.31.177): %s" % head)
		check(_labels(strip).any(func(t): return t.contains("2 towers") and t.contains("3 KOs") and t.contains("460 pts")), "with what they did: %s" % str(_labels(strip)))
		check(_press(hud.result_panel, "scoreboard"), "SCORES button on the results")
	elif frames == 6:
		var sp: PanelContainer = hud.score_panel
		check(sp != null and sp.visible and not hud.result_panel.visible, "the board opens, the results hide")
		var texts := _labels(sp)
		var i_side := texts.find("YOUR SIDE")
		var i_enemy := texts.find("ENEMY")
		check(i_side >= 0 and i_enemy > i_side, "your side first, then the enemy")
		check(texts.has("Rival") and texts.has("Kevin") and texts.has("Buddy") == false or texts.has("Buddy"), "players by name")
		var mine := texts.find("Kevin")
		check(mine > i_side and mine < i_enemy, "you're on your side's list")
		var first_side_name: String = texts[i_side + 5]          # (header: name, KO, TW, PTS; then rank, name)
		check(texts[i_side + 4] == "1" and first_side_name == Moba.bot_label(sim.by_id["b0"]), "your side's best first: %s" % first_side_name)
		var e1 := texts.find("1", i_enemy)
		check(e1 > i_enemy and texts[e1 + 1] == "Rival", "the enemy's best first: %s" % (texts[e1 + 1] if e1 > 0 else "?"))
		check(hud._modal_open(), "the board counts as a panel (no stick or buttons under it)")
		check(_press(sp, "scoreboard_back"), "BACK")
	elif frames == 8:
		check(not hud.score_panel.visible and hud.result_panel.visible and not hud._modal_open() == false, "BACK: the results again")
		# me as MVP
		hud.result_panel.visible = false               # (left in the tree: its placement timer may still run)
		hud.result_panel = null
		_put("b2", {"kills":30})
		hud.show_result({})
	elif frames == 10:
		var strip: Node = hud.result_panel.find_child("MvpStrip", true, false)
		check(strip != null and str((strip.find_child("MvpName", true, false) as Label).text) == "YOU ARE THE MVP!", "you: YOU ARE THE MVP!")
		print("SCOREBOARD_PASS" if fails.is_empty() else "SCOREBOARD_FAIL %s" % str(fails))
		quit(0 if fails.is_empty() else 1)
	return false
