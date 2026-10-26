extends SceneTree
# 0.31.220 (Kevin's 0.31.219 log: the stick and the skill buttons 3.8-5 ms a frame on his phone): each button, the
# stick, the + marks and the recall bar on a canvas item of its own under the HUD's btn_layer, drawn again only when
# what it shows changes (siege_hud.gd _btn_tick / _button_key).
#  - every button of a 5v5 hero there and shown, HOME among them (not the recall bar's item);
#  - standing still with nothing recharging: nothing drawn again for a second;
#  - Q recharging: Q drawn again as its sweep moves (in 60 steps) -- and nothing else;
#  - down: the layer hidden; a modal (the shop) open: hidden too.
#   godot --headless --fixed-fps 30 --path godot -s res://tests/hud_buttons_test.gd
const Mode = preload("res://scripts/siege/siege_mode.gd")
var mode
var frames := 0
var fails := []
var phase := 0
var mark := 0
var q_keys := {}

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")
	mode = Mode.new()
	mode.moba_hero = "knight"
	mode.match_seed = 4409
	root.add_child(mode)

func _process(_d: float) -> bool:
	frames += 1
	if mode.sim == null or not mode._build_queue.is_empty() or not mode.warmed():
		return false
	var s = mode.sim
	var hud = mode.hud
	var me: Dictionary = s.by_id["you"]
	me.bot = false
	match phase:
		0:
			# settle, everything learnt and full
			me.rk = {"q":1, "w":1, "e":1, "r":1}
			me.level = 6
			me.sp = 0
			me.cd_ability = 0.0
			me["cd_w"] = 0.0
			me["cd_e"] = 0.0
			me["ult_cd"] = 0.0
			me.cd_dodge = 0.0
			me["ward_ch"] = float(s.moba.vision.WARD_CHARGES)
			phase = 1
			mark = frames
		1:
			if frames - mark < 20:
				return false
			var ids := []
			for b in hud._buttons():
				ids.append(str(b.id))
			var shown := true
			for id in ids:
				var n = hud._btn_nodes.get(id)
				shown = shown and n != null and n.visible and n.get_parent() == hud.btn_layer
			check(shown and ids.has("recall") and ids.size() == 8, "every button on its own item, shown, HOME too (%s)" % str(ids))
			check(hud._btn_nodes.has("recall_bar") and hud._btn_nodes["recall_bar"] != hud._btn_nodes.get("recall"), "the recall bar its own item")
			check(hud.btn_layer.visible, "the layer shown while alive")
			mark = hud.btn_draws
			phase = 2
			frames = 0
		2:
			# (the ult is ready: its glow pulses -- that one item alone may redraw)
			if frames < 30:
				return false
			check(hud.btn_draws - mark <= 30 * 1 + 2, "a second with nothing changing: only the ult's glow drawn again (%d draws)" % (hud.btn_draws - mark))
			me["ult_cd"] = 30.0                     # (the ult recharging: no glow)
			me.cd_ability = 1.5                     # (under its full recharge: the sweep shows)
			q_keys = {}
			mark = hud.btn_draws
			phase = 3
			frames = 0
		3:
			q_keys[str(hud._btn_nodes["ability"].get_meta("key", []))] = true
			if frames < 30:
				return false
			check(q_keys.size() >= 4, "Q recharging: its item drawn again as the sweep moves (%d looks in a second)" % q_keys.size())
			var draws: int = hud.btn_draws - mark
			check(draws >= 4 and draws <= 70, "...and little else (%d draws in a second)" % draws)
			me.state = "dead"
			me.respawn_at = s.time + 10.0
			phase = 4
			frames = 0
		4:
			if frames < 3:
				return false
			check(not hud.btn_layer.visible, "down: the buttons hidden")
			me.state = "idle"
			me.hp = float(me.max_hp)
			hud.open_shop()
			phase = 5
			frames = 0
		5:
			if frames < 3:
				return false
			check(not hud.btn_layer.visible, "the shop open: the buttons hidden")
			hud.close_shop()
			print("HUD_BUTTONS_%s" % ("PASS" if fails.is_empty() else "FAIL %s" % str(fails)))
			quit(0 if fails.is_empty() else 1)
			return true
	if frames > 3000:
		print("HUD_BUTTONS_FAIL timeout phase %d" % phase)
		quit(1)
		return true
	return false
