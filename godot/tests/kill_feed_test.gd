extends SceneTree
# 0.31.120 (Kevin: "kill feed" and "phone vibration").
#  1. the kill feed (siege_hud.gd): knockouts "<who> ⚔ <whom>" (players by name, bots by class, you "You" on a gold
#     plate; nobody behind it: a skull), a King grabbed or rescued, a gate or the jail broken; newest first, 4 at most,
#     gone after KF_LIFE; off in the tutorial
#  2. vibration (siege_mode.gd): hit (one buzz per HIT_GAP however many land), a knockout, a multi-knockout, falling,
#     grabbing the King, a rescue, our gate falling -- nothing for other players' knocks; nothing with it off
#  3. the app: Settings > VIBRATION (on by default; off is kept), and a match gets the setting
#   godot --headless --path godot -s res://tests/kill_feed_test.gd
const Hud = preload("res://scripts/siege/siege_hud.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Mode = preload("res://scripts/siege/siege_mode.gd")
const App = preload("res://scripts/app/siege_app.gd")
const Profile = preload("res://scripts/meta/profile.gd")

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
	sim.setup(16, 4242, -1)
	hud = Hud.new()
	hud.sim = sim
	hud.player_id = "b2"
	hud.player_name = "Kevin"
	root.add_child(hud)
	hud.size = Vector2(420, 933)
	var me: Dictionary = sim.by_id["b2"]
	for u in sim.units:
		if str(u.get("cls", "")) == "oracle" or str(u.id) == "b2":
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
		check(_texts(it) == "%s  ⚔  %s" % [sim.class_label(sim.by_id[ally]), sim.class_label(sim.by_id[foe2])] and not bool(it.me)
			and (it.parts[0][1] as Color).is_equal_approx(Hud.TEAM_COLORS[hud.vt(int(sim.by_id[ally].team))].lightened(0.15)),
			"a bot knocks out a bot: their classes in their sides' colours (%s)" % _texts(it))
		_ev({"k":"death", "id":foe, "by":"b2"})
		check(_texts(hud.kill_feed[0]) == "You  ⚔  DragonSlayer99" and bool(hud.kill_feed[0].me), "I knock out a player: \"You ⚔ DragonSlayer99\", on a gold plate")
		_ev({"k":"death", "id":"b2", "by":""})
		check(_texts(hud.kill_feed[0]) == "☠ You" and bool(hud.kill_feed[0].me), "I fall with nobody behind it: a skull")
		_ev({"k":"pickup", "id":ally2, "team":1 - int(sim.by_id["b2"].team), "carry_team":int(sim.by_id["b2"].team)})
		check(_texts(hud.kill_feed[0]).ends_with(" grabbed their King"), "an ally grabs their King: %s" % _texts(hud.kill_feed[0]))
		var gi := -1
		for i in sim.gates.size():
			if int(sim.gates[i].team) == int(sim.by_id["b2"].team) and str(sim.gates[i].get("kind", "")) != "jail":
				gi = i
				break
		_ev({"k":"gate_broken", "gate":gi, "team":int(sim.gates[gi].team), "by":foe})
		check(_texts(hud.kill_feed[0]) == "DragonSlayer99 broke our %s gate" % str(sim.gates[gi].side).to_lower(), "a player breaks our gate: %s" % _texts(hud.kill_feed[0]))
		check(hud.kill_feed.size() == Hud.KF_MAX, "%d at most (newest first)" % Hud.KF_MAX)
		_ev({"k":"rescue", "id":ally, "team":int(sim.by_id["b2"].team), "n":3})
		check(_texts(hud.kill_feed[0]).ends_with(" rescued our King!") and _texts(hud.kill_feed[-1]) == "☠ You", "a rescue on top; the oldest went")
		# --- 2. vibration
		check(mode.buzzes == 0, "vibration off: no buzz for any of that")
		mode.vibrate = true
		_ev({"k":"death", "id":foe2, "by":ally})
		check(mode.buzzes == 0, "someone else's knockout: no buzz")
		_ev({"k":"death", "id":foe, "by":"b2"})
		check(mode.buzzes == 1 and mode.last_buzz == Mode.BUZZ.ko, "my knockout: %s" % str(mode.last_buzz))
		for i in 5:
			_ev({"k":"hit", "id":"b2", "by":foe, "dmg":8})
		check(mode.buzzes == 2 and mode.last_buzz == Mode.BUZZ.hit, "five hits at once: one buzz")
		_ev({"k":"hit", "id":ally, "by":foe, "dmg":8})
		check(mode.buzzes == 2, "an ally hit: no buzz")
		_ev({"k":"death", "id":"b2", "by":foe})
		check(mode.buzzes == 3 and mode.last_buzz == Mode.BUZZ.down, "I fall: the long one")
		_ev({"k":"multikill", "id":"b2", "team":int(sim.by_id["b2"].team), "n":3, "name":"TRIPLE"})
		check(mode.last_buzz == Mode.BUZZ.multi, "a multi-knockout")
		_ev({"k":"pickup", "id":"b2", "team":1, "carry_team":0})
		check(mode.last_buzz == Mode.BUZZ.king, "I grab the King")
		_ev({"k":"rescue", "id":ally, "team":int(sim.by_id["b2"].team), "n":3})
		check(mode.last_buzz == Mode.BUZZ.rescue_us, "our rescue")
		_ev({"k":"rescue", "id":foe, "team":1 - int(sim.by_id["b2"].team), "n":3})
		check(mode.last_buzz == Mode.BUZZ.rescue_them, "their rescue: a shorter one")
		var n0: int = mode.buzzes
		_ev({"k":"gate_broken", "gate":gi, "team":int(sim.gates[gi].team), "by":foe})
		check(mode.buzzes == n0 + 1 and mode.last_buzz == Mode.BUZZ.gate_us, "our gate falls")
		hud._time += Hud.KF_LIFE + 0.5
	elif frames == 4:
		check(hud.kill_feed.is_empty(), "after %d s the feed is empty" % int(Hud.KF_LIFE))
		hud.kill_feed_on = false
		_ev({"k":"death", "id":foe, "by":ally})
		check(hud.kill_feed.is_empty(), "off (the tutorial): nothing")
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
