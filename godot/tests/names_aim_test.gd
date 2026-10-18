extends SceneTree
# 0.31.177 (Kevin: "Put the player names above the players so people know if it's player or minion easier. If it's a
# bot then give bot name like "bot Alfred" for example. Also towers aren't targetable."):
#  - every seat its bot's name, ten different ones a match, the same for the same match (and from an id alone on an
#    older server's units; the server's reach the phones); over the heads: yours, and "Bot <name>" over each bot's hero -- none over a minion; the
#    live board, the results and the kill feed say "Bot <name>" too;
#  - a player's attack turns to an enemy tower that can be hurt -- standing beside one, facing away, the swing turns and
#    lands (a ranged shot from range too); not to one still guarded (the tower before it standing); a minion nearer in
#    front is still the one he swings at. The bots aim for themselves (the sim's play stays: the fingerprint's events
#    gained only the tower hit's "by"); a hit on a tower shows (chips; the damage when it's yours).
#   godot --headless --path godot -s res://tests/names_aim_test.gd
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Moba = preload("res://scripts/siege/moba.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
var mode
var frames := 0
var fails := []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

static func _fresh(hero: String, seed_v: int):
	var s = Sim.new()
	s.setup(5, seed_v)
	s.setup_moba(hero, seed_v)
	return s

static func _tower(s, team: int, tier: int, lane: int) -> Dictionary:
	for tw in s.moba.towers:
		if int(tw.team) == team and int(tw.tier) == tier and int(tw.lane) == lane:
			return tw
	return {}

static func _clear(s, me: Dictionary) -> void:
	# nobody but me anywhere near the fight
	for u in s.units:
		if u != me and int(u.team) != int(me.team):
			u.pos = Vector2(-50.0, -100.0) if int(u.team) == 1 else Vector2(50.0, 100.0)
			u.move = Vector2.ZERO

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")
	# ---- names
	var a = _fresh("knight", 77)
	var b = _fresh("knight", 77)
	var c = _fresh("knight", 78)
	var names := []
	var same := true
	var differs := false
	for hid in a.moba.heroes[0] + a.moba.heroes[1]:
		names.append(str(a.by_id[hid].get("bot_name", "")))
		same = same and str(a.by_id[hid].bot_name) == str(b.by_id[hid].bot_name)
		differs = differs or str(a.by_id[hid].bot_name) != str(c.by_id[hid].bot_name)
	var uniq := {}
	for n in names:
		uniq[n] = true
	check(names.size() == 10 and uniq.size() == 10 and not uniq.has(""), "ten seats, ten names: %s" % str(names))
	check(same and differs, "the same match the same names; another match others")
	# online: the server's names reach the phones (a phone's own draw from another seed overwritten)
	var phone = _fresh("knight", 5)
	Net.apply(phone, Net.keyframe(a), "you")
	var carried := true
	for hid in a.moba.heroes[0] + a.moba.heroes[1]:
		carried = carried and str(phone.by_id[hid].get("bot_name", "")) == str(a.by_id[hid].bot_name)
	check(carried, "the snapshot carries the server's names to the phones")
	check(Moba.bot_label({"bot_name": "Alfred"}) == "Bot Alfred" and Moba.bot_label({"id": "r2"}).begins_with("Bot ")
		and Moba.bot_label({"id": "r2"}) == Moba.bot_label({"id": "r2"}), "\"Bot Alfred\"; an older server's unit: a name from its id")
	# ---- a player's attack and the towers
	var s = _fresh("knight", 91)
	var me: Dictionary = s.by_id["you"]
	var tw := _tower(s, 1, 1, 1)                     # red's outer middle tower
	var tw2 := _tower(s, 1, 2, 1)                    # ...and the one behind it: guarded while the first stands
	check(not tw.is_empty() and s.moba.vulnerable(tw) and not s.moba.vulnerable(tw2), "red's mid towers: the outer open, the next guarded")
	var tp: Vector2 = tw.p
	var away := Vector2(0, 1)                          # (red's side is -y: stand on the blue side of it)
	me.pos = tp + away * (Moba.TOWER_R + 1.2)
	me.face = Sim.angle_of(away)                       # facing away from it
	_clear(s, me)
	var hp0 := float(tw.hp)
	var started: bool = s._start_attack(me, "attack")
	var to: Vector2 = (tp - (me.pos as Vector2)).normalized()
	check(started and Sim.dir_of(me.face).dot(to) > 0.98, "beside the tower, facing away: the attack turns to it (%.2f)" % Sim.dir_of(me.face).dot(to))
	s.drain_events()
	var by_me := false
	for i in 40:
		s.step()
		for e in s.drain_events():
			by_me = by_me or (str(e.k) == "tower_hit" and str(e.get("by", "")) == "you" and int(e.tw) == int(tw.id))
	check(float(tw.hp) < hp0 and by_me, "...and lands (%.0f -> %.0f; no minions with him: League's fifth), the hit his" % [hp0, float(tw.hp)])
	# a minion nearer, in front: that one
	s = _fresh("knight", 92)
	me = s.by_id["you"]
	tw = _tower(s, 1, 1, 1)
	tp = tw.p
	me.pos = tp + Vector2(0, 1) * (Moba.TOWER_R + 1.4)
	_clear(s, me)
	var mn: Dictionary = {}
	for u in s.units:
		if bool(u.get("minion", false)) and int(u.team) == 1:
			mn = u
			break
	if mn.is_empty():
		for u in s.units:
			if int(u.team) == 1 and not bool(u.get("hero", false)) and int(u.team) <= 1:
				mn = u
				break
	var side := Vector2(1, 0)
	me.face = Sim.angle_of(side)
	if not mn.is_empty():
		mn.pos = (me.pos as Vector2) + side * 1.0
		mn.hp = maxf(float(mn.hp), 1.0)
		mn.state = "idle"
	s._start_attack(me, "attack")
	check(mn.is_empty() or Sim.dir_of(me.face).dot(side) > 0.98, "a minion nearer, in front: he swings at it, not the tower")
	# the guarded tower: not turned to
	s = _fresh("knight", 93)
	me = s.by_id["you"]
	tw2 = _tower(s, 1, 2, 1)
	me.pos = (tw2.p as Vector2) + Vector2(0, 1) * (Moba.TOWER_R + 1.2)
	me.face = Sim.angle_of(Vector2(0, 1))
	_clear(s, me)
	s._start_attack(me, "attack")
	check(Sim.dir_of(me.face).dot(Vector2(0, 1)) > 0.98, "a guarded tower: no turn to it")
	# ranged: a Musketeer from range
	s = _fresh("musketeer", 94)
	me = s.by_id["you"]
	tw = _tower(s, 1, 1, 1)
	tp = tw.p
	me.pos = tp + Vector2(0, 1) * 8.0
	me.face = Sim.angle_of(Vector2(1, 0))
	_clear(s, me)
	hp0 = float(tw.hp)
	s._start_attack(me, "attack")
	check(Sim.dir_of(me.face).dot((tp - (me.pos as Vector2)).normalized()) > 0.98, "a Musketeer 8 m off, facing aside: turns to it")
	for i in 90:
		s.step()
	check(float(tw.hp) < hp0, "...and his shot lands (%.0f -> %.0f)" % [hp0, float(tw.hp)])
	# a bot doesn't turn by this (it aims for itself)
	s = _fresh("knight", 95)
	me = s.by_id["you"]
	me.bot = true
	tw = _tower(s, 1, 1, 1)
	me.pos = (tw.p as Vector2) + Vector2(0, 1) * (Moba.TOWER_R + 1.2)
	me.face = Sim.angle_of(Vector2(0, 1))
	_clear(s, me)
	s._start_attack(me, "attack")
	check(Sim.dir_of(me.face).dot(Vector2(0, 1)) > 0.98, "a bot's attack: not turned by it")
	# ---- over the heads, in a match
	mode = Mode.new()
	mode.moba_hero = "archmage"
	mode.match_seed = 4406
	root.add_child(mode)

func _process(_d: float) -> bool:
	frames += 1
	if mode.sim == null or not mode._build_queue.is_empty() or frames < 40:
		return false
	var s = mode.sim
	var v = mode.view
	var bots_named := 0
	var bots_seen := 0
	var minion_named := 0
	# everyone in sight of the camera for the check: bars only go to what's drawn
	for a in v.actors.values():
		if is_instance_valid(a.get("root")):
			(a.root as Node3D).visible = true
	var by_pos := {}
	for b in v.bars():
		by_pos[str(b.get("name", ""))] = true
	for u in s.units:
		if s.alive(u) and bool(u.get("hero", false)) and bool(u.get("bot", false)) and str(u.id) != "you":
			bots_seen += 1
			if by_pos.has(Moba.bot_label(u)):
				bots_named += 1
	for b in v.bars():
		var n := str(b.get("name", ""))
		if n != "" and not n.begins_with("Bot ") and n != v.my_name and not n.contains("Bone Lord") and not n.contains("Wraith") and not n.contains("Brute") and not n.contains("Wyrm"):
			minion_named += 1
	check(bots_seen == 9 and bots_named == 9, "over each bot's head: \"Bot <name>\" (%d of %d)" % [bots_named, bots_seen])
	check(minion_named == 0, "no name over a minion")
	check(by_pos.has(v.my_name), "yours over you (%s)" % v.my_name)
	# a hit on a tower shows: stone chips, and the damage when it's yours
	var tw0: Dictionary = s.moba.towers[0]
	var n0: int = v.numbers.size()
	var fx0: int = v._fx.size()
	v.on_event({"k": "tower_hit", "tw": int(tw0.id), "dmg": 42, "by": "you"})
	check(v.numbers.size() == n0 + 1 and str(v.numbers[-1].text) == "42" and (v.low_fx or v._fx.size() > fx0), "your hit on a tower: its chips and \"42\" over it")
	v.on_event({"k": "tower_hit", "tw": int(tw0.id), "dmg": 9, "by": "m_x"})
	check(v.numbers.size() == n0 + 1, "...a minion's: no number")
	var hud = mode.hud
	var b1: Dictionary = s.by_id["b1"]
	check(hud.display_name(b1) == Moba.bot_label(b1) and str(hud.kf_name("b1")[0]) == Moba.bot_label(b1),
		"the board, the results and the kill feed: %s" % hud.display_name(b1))
	print("NAMES_AIM_%s" % ("PASS" if fails.is_empty() else "FAIL %s" % str(fails)))
	quit(0 if fails.is_empty() else 1)
	return true
