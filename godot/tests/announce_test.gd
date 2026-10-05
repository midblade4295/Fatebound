extends SceneTree
# 0.31.30: the Herald's match announcements -- from your side, with cooldowns and priorities.
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")
var mode
var f := 0
var said := []
var fails := []
func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok: fails.append(what)
func _init():
	mode = Mode.new()
	root.add_child(mode)
func _process(_d):
	f += 1
	if mode._herald != null and mode._herald.stream != null:
		var nm: String = mode._herald.stream.resource_path.get_file().get_basename()
		if said.is_empty() or said[-1] != nm:
			said.append(nm)
	var s = mode.sim
	var me: Dictionary = s.by_id[mode.hud.player_id]
	var t: int = me.team
	match f:
		120:
			check(said.size() >= 1 and str(said[0]).begins_with("an_start_"), "the match opens with the start call (%s)" % str(said))
		130:
			mode._announce_event({"k":"pickup", "team":t, "carry_team":t, "id":"x"})
		600:
			check(said.any(func(x): return str(x).begins_with("an_our_pickup_")), "our King picked up by us: 'We have the King!' after the start line (%s)" % str(said))
			mode._announce_event({"k":"pickup", "team":t, "carry_team":t, "id":"x"})
			var g: int = s.gates.filter(func(x): return int(x.team) != t and str(x.get("kind", "")) != "jail")[0].id
			mode._announce_event({"k":"gate_broken", "gate":g, "team":1 - t})
		1000:
			check(said.filter(func(x): return str(x).begins_with("an_our_pickup_")).size() == 1, "the same call isn't repeated inside its cooldown")
			check(said.any(func(x): return str(x).begins_with("an_their_gate_")), "their gate down: 'Their gate is down!'")
			s.score[t] = Sim.WIN_RESCUES - 1
			mode._announce_event({"k":"rescue", "team":t, "id":"x", "n":1})
		1010:
			check(str(said[-1]).begins_with("an_our_rescue_"), "our rescue cuts straight in (%s)" % said[-1])
		1500:
			check(said.has("an_match_point_us_1"), "then 'One more rescue and we win!' (%s)" % str(said))
			mode._announce_event({"k":"outpost_captured", "id":0, "team":t})
		1800:
			check(said.any(func(x): return str(x).begins_with("an_our_outpost_")), "a tower taken by us is called (0.31.31)")
			mode._announce_event({"k":"outpost_lost", "id":1, "team":t})
		2100:
			check(said.any(func(x): return str(x).begins_with("an_their_outpost_")), "losing one of ours is called")
		2110:
			print("ANNOUNCE_PASS" if fails.is_empty() else "ANNOUNCE_FAIL %s" % str(fails))
			quit(0 if fails.is_empty() else 1)
	return false
