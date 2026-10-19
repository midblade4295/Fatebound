extends SceneTree
# 0.31.180 (Kevin: "Make banner in middle of screen when a player kills another player ... I want the banner art
# created by eleven ... special effects on the kill streak and first blood ones"): siege_hud.gd's kill banners
# (kill_banner.gd) and the live board's bounty badge, in a real 5v5.
#  - a kill: the plaque, "<killer> HAS SLAIN <victim>" in the HUD's names (yours, "Bot <name>"); FIRST BLOOD, DOUBLE ..
#    PENTAKILL, SHUTDOWN and ACE each with their painted art (assets/ui/banners) and their effects (blood, sparks,
#    coins, confetti, rays);
#  - one at a time: a newer one cuts the showing one short after a moment; a long run drops the plain kills first;
#  - the bots' own fights: their kills put banners up;
#  - the board: a gold badge with a hero's bounty from 150 (steps of 50), none under.
#   godot --headless --path godot -s res://tests/kill_banner_test.gd
const Mode = preload("res://scripts/siege/siege_mode.gd")
var mode
var frames := 0
var phase := "boot"
var mark := 0
var fails := []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")
	mode = Mode.new()
	mode.moba_hero = "knight"
	mode.match_seed = 4410
	root.add_child(mode)

func _reset(kb) -> void:
	kb.queue.clear()
	kb.cur = {}
	kb.parts.clear()
	kb.shown.clear()

func _process(delta: float) -> bool:
	frames += 1
	if mode.sim == null or not mode._build_queue.is_empty() or frames < 30:
		return false
	var s = mode.sim
	var hud = mode.hud
	var kb = hud.kill_banner
	var t := int(s.by_id["you"].team)
	var foe: Array = s.moba.heroes[1 - t]
	match phase:
		"boot":
			check(kb != null and kb.get_parent() == hud, "the HUD has its kill banner")
			for st in ["plaque_blue", "plaque_red", "first_blood", "double", "triple", "quadra", "penta", "ace", "shutdown"]:
				check(kb.tex(st) != null, "art: %s" % st)
			hud.player_name = "Midblade"
			_reset(kb)
			hud.on_event({"k":"kb", "kind":"kill", "n":1, "by":"you", "id":str(foe[0])})
			phase = "kill"
			mark = frames
		"kill":
			if frames - mark < 3:
				return false
			var nm: Array = kb.line_names()
			check(kb.busy() and str(kb.cur.style) == "kill" and not kb._art.visible, "a kill: the plaque alone")
			check(nm[0] == "Midblade" and nm[1] == s.moba.bot_label(s.by_id[str(foe[0])]), "\"%s HAS SLAIN %s\"" % [nm[0], nm[1]])
			# every kind: its art and its effects
			var kinds := [["first_blood", {"kind":"first_blood"}, "blood"], ["double", {"kind":"multi", "n":2}, "spark"],
				["triple", {"kind":"multi", "n":3}, "ember"], ["quadra", {"kind":"multi", "n":4}, "coin"],
				["penta", {"kind":"multi", "n":5}, "confetti"], ["shutdown", {"kind":"shutdown", "bounty":450, "shut":true}, "coin"]]
			var good := true
			for kd in kinds:
				_reset(kb)
				var e: Dictionary = {"k":"kb", "n":1, "by":"you", "id":str(foe[1])}
				e.merge(kd[1], true)
				kb.push(e)
				kb._process(0.02)
				var has := false
				for p in kb.parts:
					has = has or str(p.kind) == str(kd[2])
				var ok: bool = str(kb.cur.get("style", "")) == str(kd[0]) and kb._art.visible and kb._art.texture == kb.tex(str(kd[0])) and has
				print("   %-12s art %s, %d particles (%s)" % [kd[0], str(kb._art.visible), kb.parts.size(), str(kd[2])])
				good = good and ok
			check(good, "FIRST BLOOD, DOUBLE..PENTAKILL, SHUTDOWN: each its art and its effects")
			_reset(kb)
			kb.push({"k":"ace", "team":t, "by":"you", "ids":foe})
			kb._process(0.02)
			check(str(kb.cur.style) == "ace" and kb._art.visible, "ACE: its crest and the five fallen")
			# one at a time; a newer one cuts in
			_reset(kb)
			kb.push({"k":"kb", "kind":"kill", "n":1, "by":"you", "id":str(foe[0])})
			kb._process(0.02)
			kb.push({"k":"kb", "kind":"multi", "n":2, "by":"you", "id":str(foe[1])})
			check(str(kb.cur.style) == "kill" and kb.queue.size() == 1, "a second waits its turn")
			for i in 70:
				kb._process(0.02)                       # (1.4 s)
			check(kb.shown == ["kill", "double"], "...and comes in once the first has had a moment (%s)" % str(kb.shown))
			_reset(kb)
			kb.cur = {"style":"triple", "life":3.0}
			kb.age = 1.0
			for i in 6:
				kb.push({"k":"kb", "kind":"kill", "n":1, "by":"you", "id":str(foe[0])})
			kb.push({"k":"kb", "kind":"multi", "n":4, "by":"you", "id":str(foe[1])})
			var styles: Array = kb.queue.map(func(q): return str(q.style))
			check(kb.queue.size() == 4 and styles.has("quadra"), "a long run: four waiting at most, the QUADRA kept (%s)" % str(styles))
			_reset(kb)
			# the bots' own fights: banners from real kills
			for u in s.units:
				if bool(u.get("hero", false)):
					u.bot = true
			mode.hud.kill_banner.shown.clear()
			phase = "bots"
			mark = frames
		"bots":
			# a few minutes of the bots, their events through the HUD as in a match
			for i in 40:
				s.step()
				for e in s.drain_events():
					hud.on_event(e)
			kb._process(0.05)
			if s.time < 330.0 and not s.ended:
				return false
			check(not kb.shown.is_empty() and kb.shown[0] == "first_blood", "5:30 of bots: the banners came up, FIRST BLOOD first (%s)" % str(kb.shown.slice(0, 6)))
			# the board's bounty badge
			var r1: Dictionary = s.by_id[str(foe[1])]
			var r2: Dictionary = s.by_id[str(foe[2])]
			r1.bounty = 420.0
			r2.bounty = 120.0
			for hid in s.moba.heroes[0] + s.moba.heroes[1]:
				s.by_id[hid].gold = 1000.0
				s.by_id[hid].items = []
			hud.open_board()
			hud._refresh_board()
			var row1: Dictionary = hud._board_rows[str(foe[1])]
			var row2: Dictionary = hud._board_rows[str(foe[2])]
			check(row1.bounty_box.visible and row1.bounty.text == "400" and not row2.bounty_box.visible,
				"the board: a 420 bounty shows 400, a 120 none")
			print("KILL_BANNER_%s" % ("PASS" if fails.is_empty() else "FAIL %s" % str(fails)))
			quit(0 if fails.is_empty() else 1)
			return true
	return false
