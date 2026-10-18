extends SceneTree
# 0.31.172: review shots of the towers breaking (towers.gd) -- from the match's own camera or close (CLOSE=1).
#   Xvfb :98 & DISPLAY=:98 godot --rendering-method mobile --resolution 900x1600 --path godot -s res://tools/tower_shots.gd
# TW (tower id, default 3: blue's middle outer tower; 9 / 10 blue's King towers; red's are 11 on, drawn red), OUT
# (prefix, default /tmp/tower_), CLOSE=1 (a closer camera). Shots: whole, then at 70 / 45 / 20 % health and fallen,
# each just after the break (pieces in the air: <n>_fall) and when they've settled (<n>).
const Mode = preload("res://scripts/siege/siege_mode.gd")
var mode
var frames := 0
var tw_id := 3
var prefix := "/tmp/tower_"
var t0 := -1
var pending := ""
# [frames after the start, health fraction to set (or -1), shot name (or "")]
const PLAN := [[0, -1.0, "0_whole"], [10, 0.70, ""], [19, -1.0, "1_fall"], [90, -1.0, "1"], [100, 0.45, ""], [109, -1.0, "2_fall"],
	[180, -1.0, "2"], [190, 0.20, ""], [199, -1.0, "3_fall"], [270, -1.0, "3"], [280, 0.0, ""], [289, -1.0, "4_fall"], [380, -1.0, "4"]]

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")
	if OS.has_environment("TW"):
		tw_id = int(OS.get_environment("TW"))
	if OS.has_environment("OUT"):
		prefix = OS.get_environment("OUT")
	mode = Mode.new()
	mode.moba_hero = "knight"
	mode.match_seed = 4402
	root.add_child(mode)
	RenderingServer.frame_post_draw.connect(func():
		if pending != "":
			root.get_texture().get_image().save_png("%s%s.png" % [prefix, pending])
			var tw: Dictionary = mode.sim.moba.towers[tw_id]
			var mt: Dictionary = mode.view.moba_towers.get(tw_id, {})
			print("SHOT ", pending, " hp ", int(tw.hp), "/", int(tw.max_hp), " stage ", mt.get("stage", -9), " falling ",
				mode.view._falling.size())
			pending = "")

func _process(_delta: float) -> bool:
	frames += 1
	if mode.sim == null or not mode._build_queue.is_empty() or frames < 40:
		return false
	var s = mode.sim
	var tw: Dictionary = s.moba.towers[tw_id]
	if frames == 40:
		s.moba.wave_at = INF
		for c in s.moba.camps:
			c.next = INF
		var me: Dictionary = s.by_id["you"]
		var p: Vector2 = tw.p
		var away: Vector2 = (Vector2.ZERO - p).normalized() if p.length() > 1.0 else Vector2(0, -1)
		me.pos = p + away * 5.5 + Vector2(2.0, 0.0)
		for u in s.units:
			if u != me and bool(u.get("hero", false)):
				u.bot = false
				u.pos = s.spawn(int(u.team))
				u.move = Vector2.ZERO
				u.task = {}
		if OS.get_environment("CLOSE") == "1":
			var top := Vector3(p.x, 3.0, p.y)
			mode.view.cam_override = [top + Vector3(away.x * 9.0 + 3.0, 6.5, away.y * 9.0), top]
		return false
	if t0 < 0:
		t0 = frames + 30
	var t := frames - t0
	for st in PLAN:
		if int(st[0]) != t:
			continue
		var f := float(st[1])
		if f >= 0.0:
			tw.hp = float(tw.max_hp) * f
			if f <= 0.0 and not bool(tw.dead):
				tw.dead = true
				s._event("tower_down", {"tw":tw_id, "team":int(tw.team), "lane":int(tw.lane), "tier":int(tw.tier), "by":"you"})
		if str(st[2]) != "":
			pending = str(st[2])
	if t > int(PLAN[PLAN.size() - 1][0]) + 3:
		quit(0)
		return true
	return false
