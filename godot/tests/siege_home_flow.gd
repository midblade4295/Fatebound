extends SceneTree
# Home -> ENTER BATTLE (Siege) -> match end -> rewards credited to the save -> HOME.
const Client = preload("res://scripts/full_client.gd")
var app
var frames := 0
var gold0 := 0
var xp0 := 0
var lvl0 := 0
var chests0 := 0
var pts0 := 0
func find_button(key: String, node: Node = null) -> Button:
	if node == null: node = app
	if node is Button and str(node.get_meta("action_key", "")) == key: return node
	for c in node.get_children():
		var r := find_button(key, c)
		if r != null: return r
	return null
func _init() -> void:
	app = Client.new()
	app.autoload_network = false
	app._save_path_override = "user://siege-home-flow-%d.json" % Time.get_ticks_usec()
	root.add_child(app)
func _process(delta: float) -> bool:
	frames += 1
	if frames == 10:
		for k in ["prepare", "raid", "training"]:
			assert(find_button(k) == null, "dice-mode entry still on home: " + k)
		var b := find_button("siege")
		assert(b != null, "no ENTER BATTLE (siege) button on home")
		gold0 = int(app.d.gold); xp0 = int(app.d.xp); lvl0 = int(app.d.level); chests0 = app.d.chests.size(); pts0 = int(app.d.season.pts)
		b.pressed.emit()
	if frames == 20:
		assert(app.screen == "siege" and is_instance_valid(app.siege), "siege did not start from home")
		var s = app.siege.sim
		s.by_id["you"].kills = 3
		s.score = [3, 1]
		s._finish("rescue")
	if frames == 30:
		var r: Dictionary = app.siege.rewards
		assert(r.gold == 120 + 12 and r.xp == 60 and r.chest == 1, "reward formula " + str(r))
		assert(int(app.d.gold) == gold0 + int(r.gold), "gold not credited")
		assert(app.d.chests.size() == chests0 + 1, "chest not credited")
		assert(int(app.d.season.pts) == pts0 + 12, "season points not credited")
		assert(int(app.d.xp) != xp0 or int(app.d.level) != lvl0, "xp not credited")
		assert(app.siege.hud.result_panel != null and app.siege.hud.result_panel.visible, "no result panel")
		print("rewards=", r, " gold ", gold0, "->", app.d.gold)
		app.siege.hud.replay_requested.emit()
	if frames == 40:
		assert(not app.siege.sim.ended, "play again did not start a new match")
		assert(int(app.d.gold) == gold0 + int(app.siege.rewards.gold), "play again re-granted rewards")
		app.siege.hud.leave_requested.emit()
	if frames == 50:
		assert(app.screen == "home", "HOME did not return to home: " + app.screen)
		print("SIEGE_HOME_FLOW_PASS")
		quit(0)
	return false
