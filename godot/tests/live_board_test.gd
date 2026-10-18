extends SceneTree
# 0.31.176 (Kevin: "I'm wanting to give players ability to pull up live score anytime in match. Make a scoreboard that
# gives the stats that league of legends does" -> concept A, opened by tapping the score bar): siege_hud.gd's live board.
#  - the sim keeps what League's board shows: assists (the helpers a knockout's gold is shared with), each side's Bone
#    Lords and Grave Wyrms slain (moba.epic_kills) -- and the snapshot carries them to the phones ("ek");
#  - a 5v5 played by bots to 6:00, then the score bar tapped: the board, the match running under it; your side first;
#    each side's strip (knockouts, enemy towers down, epics, gold and the lead) and five rows by role -- level, K / D / A,
#    CS, the items, gold -- matching the sim, live (a knockout added shows within a refresh); a hero who is down greyed
#    with the seconds to his return; the bar again closes it, and a tap outside it.
#   godot --headless --path godot -s res://tests/live_board_test.gd     (SHOT_DIR=... with a display: a picture)
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Hud = preload("res://scripts/siege/siege_hud.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")
var mode
var frames := 0
var phase := "boot"
var t_mark := 0
var fails := []
var shots := ""

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")
	check(Hud.net_worth({"gold": 150.0, "items": ["sword", "bloodthirster"]}) == 150 + 350 + 1900 and Hud.gold_k(5640.0) == "5.6k",
		"a hero's gold: what he carries and his items' cost")
	mode = Mode.new()
	mode.moba_hero = "archmage"
	mode.match_seed = 4405
	root.add_child(mode)

func _tap(p: Vector2) -> void:
	mode.hud._touch(0, p, true)
	mode.hud._touch(0, p, false)

func _process(_d: float) -> bool:
	frames += 1
	if shots == "" and DisplayServer.get_name() != "headless" and OS.has_environment("SHOT_DIR"):
		shots = OS.get_environment("SHOT_DIR")
	if mode.sim == null or not mode._build_queue.is_empty() or frames < 30:
		return false
	var s = mode.sim
	var hud = mode.hud
	match phase:
		"boot":
			s.by_id["you"].bot = true
			while s.time < 360.0 and not s.ended:
				s.step()
			s.drain_events()
			var asst := 0
			for u in s.units:
				if bool(u.get("hero", false)):
					asst += int(u.get("assists", 0))
			check(int(s.kills[0]) + int(s.kills[1]) > 0 and asst > 0, "6:00 of bots: knockouts %s, assists counted (%d)" % [str(s.kills), asst])
			# the epic monsters by side, in the snapshot
			s.moba.epic_kills.lord[0] = 1
			s.moba.epic_kills.wyrm[1] = 2
			var snap: Dictionary = Net.snapshot(s, "", [])
			var phone = Sim.new()
			phone.setup(5, 4405)
			phone.setup_moba("archmage", 4405)
			Net.apply(phone, Net.keyframe(s), "you")
			check(snap.has("ek") and int(phone.moba.epic_kills.lord[0]) == 1 and int(phone.moba.epic_kills.wyrm[1]) == 2,
				"the snapshot carries each side's epic monsters to the phones")
			var same := true
			var some := 0
			for u in s.units:
				if bool(u.get("hero", false)):
					some += int(u.get("assists", 0))
					same = same and phone.by_id.has(u.id) and int(phone.by_id[u.id].get("assists", 0)) == int(u.get("assists", 0))
			check(same and some > 0, "...and every hero's assists")
			# someone down, for the timer
			var victim: Dictionary = s.by_id[str(s.moba.heroes[1][0])]
			if s.alive(victim):
				victim.hp = 0.0
				victim.state = "dead"
				victim.respawn_at = s.time + 12.0
			phase = "open"
			t_mark = frames
		"open":
			if frames - t_mark < 3:
				return false
			check(not hud.board_open(), "no board until asked")
			_tap(hud.score_bar_rect().get_center())
			check(hud.board_open() and hud.board_panel.position.y >= hud.score_bar_rect().end.y, "the score bar tapped: the board, under the bar")
			var rows: Dictionary = hud._board_rows
			check(rows.size() == 10, "ten rows (%d)" % rows.size())
			# your side first, then the enemy; each by role
			var order := []
			for c in hud.board_panel.find_children("*", "PanelContainer", true, false):
				if c.has_meta("unit"):
					order.append(str(c.get_meta("unit")))
			var my_team := int(s.by_id["you"].team)
			var first5 := order.slice(0, 5).all(func(id): return int(s.by_id[id].team) == my_team)
			check(order.size() == 10 and first5 and order.has("you"), "your side first (%s)" % str(order))
			var good := true
			for id in rows:
				var u: Dictionary = s.by_id[id]
				var r: Dictionary = rows[id]
				good = good and r.k.text == str(int(u.kills)) and r.d.text == str(int(u.deaths)) and r.a.text == str(int(u.get("assists", 0))) \
					and r.cs.text == str(int(u.get("lh", 0))) and r.lv.text == str(int(u.level)) and r.gold.text == Hud.gold_k(float(Hud.net_worth(u)))
				var inv: Array = u.get("items", [])
				for i in 6:
					good = good and (r.slots[i] as Control).item == (str(inv[i]) if i < inv.size() else "")
			check(good, "every row as the sim has it: level, K / D / A, CS, items, gold")
			var hd: Dictionary = hud._board_heads[0]
			var bt: Dictionary = hud.board_team(my_team)
			check(hd.kills.text == str(int(s.kills[my_team])) and hd.towers.text == str(int(bt.towers)) and hd.gold.text == Hud.gold_k(float(bt.gold))
				and str(hd.epics.text).contains("LORD") and str(hud._board_heads[1].epics.text).contains("WYRM"),
				"each side's strip: knockouts %s, towers %d, epics, gold %s" % [hd.kills.text, int(bt.towers), hd.gold.text])
			var vid := str(s.moba.heroes[1][0])
			check(rows[vid].resp.text != "" and int(rows[vid].resp.text) > 0 and rows[vid].resp.text.to_int() <= 12, "a hero down: greyed, %s s to his return" % rows[vid].resp.text)
			# live: the match goes on under it
			s.by_id["you"].kills = int(s.by_id["you"].kills) + 1
			phase = "live"
			t_mark = frames
		"live":
			if frames - t_mark < 20:
				return false
			check(hud._board_rows["you"].k.text == str(int(s.by_id["you"].kills)), "live: your knockout shows while it's open")
			if shots != "":
				root.get_viewport().get_texture().get_image().save_png(shots.path_join("live_board.png"))
			_tap(hud.score_bar_rect().get_center())
			check(not hud.board_open(), "the score bar again: closed")
			_tap(hud.score_bar_rect().get_center())
			check(hud.board_open(), "...and open")
			_tap(Vector2(hud.size.x * 0.5, hud.size.y - 6.0))
			var outside: bool = not hud.board_panel.get_global_rect().has_point(Vector2(hud.size.x * 0.5, hud.size.y - 6.0) + hud.global_position)
			check(outside and not hud.board_open(), "a tap outside it: closed")
			print("LIVE_BOARD_%s" % ("PASS" if fails.is_empty() else "FAIL %s" % str(fails)))
			quit(0 if fails.is_empty() else 1)
			return true
	return false
