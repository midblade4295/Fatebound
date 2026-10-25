extends SceneTree
# 0.31.120 (Kevin: "kill feed" and "phone vibration").
#  1. the kill feed (siege_hud.gd): knockouts "<who> ⚔ <whom>" (players by name, bots by class -- 0.31.177: a 5v5's bot
#     heroes by their bots' names, "Bot <name>" -- you "You" on a gold
#     plate; nobody behind it: a skull), a tower fallen, a gate broken, the Bone Lord slain; newest first, 4 at most,
#     gone after KF_LIFE; off when a match turns it off
#  2. vibration (siege_mode.gd): 0.31.128 -- only my knockouts buzz (one each); nothing for being hit, falling, a
#     multi-knockout's banner, a tower or a gate; nothing for other players' knocks; nothing with it off
# (0.31.169: a 5v5 -- Siege's King grabbed and rescued went with it)
#  3. the app: Settings > VIBRATION (on by default; off is kept), and a match gets the setting
#   godot --headless --path godot -s res://tests/kill_feed_test.gd
const Hud = preload("res://scripts/siege/siege_hud.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Mode = preload("res://scripts/siege/siege_mode.gd")
const App = preload("res://scripts/app/siege_app.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const Moba = preload("res://scripts/siege/moba.gd")

var fails: Array = []
var hud
var sim
var mode
var app
var frames := 0
var ally := ""
var ally2 := ""
var foe := ""
var foe2 := ""

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	sim = Sim.new()
	sim.setup(5, 4242, -1)
	sim.setup_moba("", 4242)
	hud = Hud.new()
	hud.sim = sim
	hud.player_id = "b2"
	hud.player_name = "Kevin"
	root.add_child(hud)
	hud.size = Vector2(933, 420)
	var me: Dictionary = sim.by_id["b2"]
	for u in sim.units:
		if not bool(u.get("hero", false)) or str(u.id) == "b2":
			continue
		if int(u.team) == int(me.team):
			if ally == "":
				ally = str(u.id)
			elif ally2 == "":
				ally2 = str(u.id)
		else:
			if foe == "":
				foe = str(u.id)
			elif foe2 == "":
				foe2 = str(u.id)
	hud.net_names = {foe: "DragonSlayer99"}
	mode = Mode.new()
	mode.sim = sim
	mode.hud = hud

func _texts(it: Dictionary) -> String:
	return "".join((it.parts as Array).map(func(p): return str(p[0])))

func _ev(e: Dictionary) -> void:
	hud.on_event(e)
	mode._count(e)

func _process(_d: float) -> bool:
	frames += 1
	if frames == 2:
		# --- 1. the feed
		_ev({"k":"death", "id":foe2, "by":ally})
		var it: Dictionary = hud.kill_feed[0]
		check(_texts(it) == "%s  ⚔  %s" % [Moba.bot_label(sim.by_id[ally]), Moba.bot_label(sim.by_id[foe2])] and not bool(it.me)
			and _texts(it).begins_with("Bot ")
			and (it.parts[0][1] as Color).is_equal_approx(Hud.TEAM_COLORS[hud.vt(int(sim.by_id[ally].team))].lightened(0.15)),
			"a bot knocks out a bot: their bots' names in their sides' colours (%s)" % _texts(it))
		_ev({"k":"death", "id":foe, "by":"b2"})
		check(_texts(hud.kill_feed[0]) == "You  ⚔  DragonSlayer99" and bool(hud.kill_feed[0].me), "I knock out a player: \"You ⚔ DragonSlayer99\", on a gold plate")
		_ev({"k":"death", "id":"b2", "by":""})
		check(_texts(hud.kill_feed[0]) == "☠ You" and bool(hud.kill_feed[0].me), "I fall with nobody behind it: a skull")
		_ev({"k":"tower_down", "team":1 - int(sim.by_id["b2"].team), "lane":1, "tier":1})
		check(_texts(hud.kill_feed[0]) == "Their middle outer tower fell", "their tower falls: %s" % _texts(hud.kill_feed[0]))
		var gi := -1
		for i in sim.gates.size():
			if int(sim.gates[i].team) == int(sim.by_id["b2"].team):
				gi = i
				break
		_ev({"k":"gate_broken", "gate":gi, "team":int(sim.gates[gi].team), "by":foe})
		check(_texts(hud.kill_feed[0]) == "DragonSlayer99 broke our %s gate" % str(sim.gates[gi].side).to_lower(), "a player breaks our gate: %s" % _texts(hud.kill_feed[0]))
		check(hud.kill_feed.size() == Hud.KF_MAX, "%d at most (newest first)" % Hud.KF_MAX)
		_ev({"k":"lord_down", "by":ally, "team":int(sim.by_id["b2"].team)})
		check(_texts(hud.kill_feed[0]).ends_with(" slew the Bone Lord") and _texts(hud.kill_feed[-1]) == "☠ You", "the Bone Lord slain on top; the oldest went")
		# --- 2. vibration
		check(mode.buzzes == 0, "vibration off: no buzz for any of that")
		mode.vibrate = true
		_ev({"k":"death", "id":foe2, "by":ally})
		check(mode.buzzes == 0, "someone else's knockout: no buzz")
		_ev({"k":"death", "id":foe, "by":"b2"})
		check(mode.buzzes == 1 and mode.last_buzz == Mode.BUZZ.ko, "my knockout: %s" % str(mode.last_buzz))
		_ev({"k":"death", "id":foe2, "by":"b2"})
		check(mode.buzzes == 2, "another knockout: another buzz")
		# 0.31.128 (Kevin: "I only want phone to vibrate when player makes a kill"): nothing else buzzes
		var n0: int = mode.buzzes
		for i in 5:
			_ev({"k":"hit", "id":"b2", "by":foe, "dmg":8})
		_ev({"k":"death", "id":"b2", "by":foe})
		_ev({"k":"multikill", "id":"b2", "team":int(sim.by_id["b2"].team), "n":3, "name":"TRIPLE"})
		_ev({"k":"tower_down", "team":int(sim.by_id["b2"].team), "lane":0, "tier":1})
		_ev({"k":"gate_broken", "gate":gi, "team":int(sim.gates[gi].team), "by":foe})
		check(mode.buzzes == n0, "no buzz when hit, knocked out, for a multi-knockout's banner, a tower or a gate")
		hud._time += Hud.KF_LIFE + 0.5
	elif frames == 4:
		check(hud.kill_feed.is_empty(), "after %d s the feed is empty" % int(Hud.KF_LIFE))
		hud.kill_feed_on = false
		_ev({"k":"death", "id":foe, "by":ally})
		check(hud.kill_feed.is_empty(), "off: nothing")
		mode.free()
		# --- 3. the app
		var base := "user://kftest-%d" % Time.get_ticks_usec()
		var p = Profile.new(base + "-profile.json", base + "-none.json")
		p.load_or_create()
		p.d.tutorial_done = true
		p.save()
		app = App.new()
		app.profile_path = base + "-profile.json"
		app.legacy_path = base + "-none.json"
		root.add_child(app)
	elif frames == 8:
		app.show_tab("settings")
		var t: Array = app.find_children("*", "Button", true, false).filter(func(b): return str(b.get_meta("action_key", "")) == "vibrate")
		check(t.size() == 1 and (t[0] as Button).button_pressed, "Settings: VIBRATION, on by default")
		if t.size() == 1:
			(t[0] as Button).button_pressed = false             # (emits toggled)
	elif frames == 10:
		check(not bool(app.profile.d.settings.get("vibrate", true)), "turned off: kept")
		app.start_match(false)
		check(app.siege != null and not bool(app.siege.vibrate), "a match gets the setting")
	elif frames == 14:
		print("KILL_FEED_PASS" if fails.is_empty() else "KILL_FEED_FAIL %s" % str(fails))
		quit(0 if fails.is_empty() else 1)
	return false
