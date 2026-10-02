extends SceneTree
# Loose logs and rocks (0.31.0): a felled tree drops logs and a broken boulder drops rocks; walking into them pushes them;
# they roll downhill (logs float down the river); a Worker picks one up with ACTION and banks it as before.
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Land = preload("res://scripts/siege/siege_land.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
var fails := []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _fresh(seed_n := 5) -> Object:
	var s = Sim.new()
	s.setup(6, seed_n)
	for u in s.units:
		u.bot = false
		u.move = Vector2.ZERO
		u.pos = Sim.spawn(u.team) + Vector2(randf_range(-6, 6), 0)
	return s

func _steps(s, n: int) -> void:
	for i in n:
		s.step()

func _init() -> void:
	var s = _fresh()
	var w: Dictionary = s.units.filter(func(u): return u.team == 0)[0]
	s._set_class(w, "worker", false)
	var tree: Dictionary = s.nodes.filter(func(n): return n.kind == "wood")[0]
	w.pos = (tree.p as Vector2) + Vector2(tree.r + 0.7, 0)
	check(s.context_action(w) == "chop", "a Worker at a tree is offered CHOP")
	var swings := 0
	for i in 40:
		if w.task.is_empty() and int(tree.amount) > 0:
			s.act(w.id, "interact")
			swings += 1
		_steps(s, int(Sim.GATHER_TIME / Sim.TICK) + 1)
		if int(tree.amount) <= 0:
			break
	var logs: Array = s.items.filter(func(it): return it.kind == "log")
	check(int(tree.amount) <= 0 and logs.size() == Sim.LOGS_PER_TREE, "the tree comes down into %d logs (%d)" % [Sim.LOGS_PER_TREE, logs.size()])
	check(int(w.load.n) == 0, "chopping alone doesn't fill the Worker's arms")
	# pushing
	_steps(s, 60)
	var lg: Dictionary = logs[0]
	var p0: Vector2 = lg.pos
	var walker: Dictionary = s.units.filter(func(u): return u.team == 0)[1]
	var axis: Vector2 = s._item_axis(lg)
	var side := Vector2(-axis.y, axis.x)
	walker.pos = p0 - side * 2.0
	walker.move = side
	_steps(s, 45)
	walker.move = Vector2.ZERO
	var moved: float = ((lg.pos as Vector2) - p0).dot(side)
	check(moved > 0.8, "walking into a log rolls it ahead (%.2f m)" % moved)
	_steps(s, 90)
	var rest: Vector2 = lg.pos
	_steps(s, 30)
	check(((lg.pos as Vector2) - rest).length() < 0.15 or s.water_depth(lg.pos) > 0.15 or s._ground_grad(lg.pos).length() > 0.05, "and then it settles (unless on a slope or in the river)")
	# slope: a log on the west hill's flank rolls downhill
	var hill := Vector2(-33.0, 25.0)
	var spot := hill + Vector2(10.5, 0.0)
	var g0: Vector2 = s._ground_grad(spot)
	s.items.append({"id":900, "kind":"log", "res":"wood", "pos":spot, "vel":Vector2.ZERO, "ang":PI * 0.5, "spin":0.0, "roll":0.0, "rax":0.0, "born":s.time, "val":2})
	var sl: Dictionary = s.items[s.items.size() - 1]
	var h0: float = Sim.height_at(spot)
	_steps(s, 60)
	check(Sim.height_at(sl.pos) < h0 - 0.1, "a log on a hillside rolls downhill (%.2f -> %.2f m, slope %.2f)" % [h0, Sim.height_at(sl.pos), g0.length()])
	# river: logs float off downstream
	var rp := Vector2(-30.0, Land.river_c(-30.0))
	s.items.append({"id":901, "kind":"log", "res":"wood", "pos":rp, "vel":Vector2.ZERO, "ang":0.0, "spin":0.0, "roll":0.0, "rax":0.0, "born":s.time, "val":2})
	var fl: Dictionary = s.items[s.items.size() - 1]
	_steps(s, 90)
	check((fl.pos as Vector2).x < rp.x - 1.0, "a log in the river floats off downstream (x %.1f -> %.1f)" % [rp.x, (fl.pos as Vector2).x])
	# pick up: Workers only, three logs at most
	s.items.erase(sl)
	s.items.erase(fl)
	var knight: Dictionary = s.units.filter(func(u): return u.team == 0)[2]
	s._set_class(knight, "knight", false)
	var near_log: Dictionary = s.items.filter(func(it): return it.kind == "log")[0]
	knight.pos = (near_log.pos as Vector2) + Vector2(0.0, 0.9)
	check(s.context_action(knight) != "pick_up", "a Knight can't pick logs up")
	var got := 0
	for k in 4:
		var avail: Array = s.items.filter(func(it): return it.kind == "log")
		if avail.is_empty():
			break
		w.task = {}
		w.state = "idle"
		w.pos = (avail[0].pos as Vector2) + Vector2(0.0, 0.8)
		if s.context_action(w) == "pick_up" and s.act(w.id, "interact"):
			got += 1
	check(got == 3 and int(w.load.n) == 3 * Sim.ITEM_VALUE and w.load.kind == "wood", "a Worker picks up logs with ACTION, three at most (%d, load %d)" % [got, int(w.load.n)])
	var wood0: int = int(s.stock[0].wood)
	w.pos = s.workshop(0)
	_steps(s, 3)
	check(int(s.stock[0].wood) == wood0 + 3 * Sim.ITEM_VALUE and int(w.load.n) == 0, "and banks them at the workshop")
	# regrowth
	s.time += Sim.NODE_REGROW["wood"]
	tree.t = Sim.NODE_REGROW["wood"]
	_steps(s, 2)
	check(int(tree.amount) == int(tree.max), "the tree grows back")
	# boulders break into rocks
	var s2 = _fresh(9)
	var w2: Dictionary = s2.units.filter(func(u): return u.team == 0)[0]
	s2._set_class(w2, "worker", false)
	var rock: Dictionary = s2.nodes.filter(func(n): return n.kind == "stone")[0]
	w2.pos = (rock.p as Vector2) + Vector2(rock.r + 0.7, 0)
	check(s2.context_action(w2) == "mine", "a Worker at a boulder is offered MINE")
	for i in 60:
		if w2.task.is_empty() and int(rock.amount) > 0:
			s2.act(w2.id, "interact")
		_steps(s2, int(Sim.GATHER_TIME / Sim.TICK) + 1)
		if int(rock.amount) <= 0:
			break
	check(s2.items.filter(func(it): return it.kind == "rock").size() == Sim.ROCKS_PER_BOULDER, "the boulder breaks into %d rocks" % Sim.ROCKS_PER_BOULDER)
	# online: the items travel in the snapshot
	var snap: Dictionary = Net.snapshot(s2, str(w2.id), [])
	var s3 = _fresh(9)
	Net.apply(s3, snap, str(w2.id))
	check(s3.items.size() == s2.items.size() and (s3.items[0].pos as Vector2).distance_to(s2.items[0].pos) < 0.02, "loose rocks reach online players (%d)" % s3.items.size())
	# bots: workers still keep the stockpile growing
	var s4 = Sim.new()
	s4.setup(8, 13)
	var st0: int = int(s4.stock[0].wood) + int(s4.stock[0].stone)
	var dv := 0
	for i in int(240.0 / Sim.TICK):
		s4.step()
		for e in s4.drain_events():
			if str(e.get("k", "")) == "deliver":
				dv += int(e.get("n", 0))
	check(dv >= 20, "worker bots fell trees, pick up the logs and rocks and deliver them (%d delivered in 4 minutes)" % dv)
	print("ITEMS_PASS" if fails.is_empty() else "ITEMS_FAIL %d" % fails.size())
	quit()
