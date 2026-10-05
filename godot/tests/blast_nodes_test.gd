extends SceneTree
# 0.31.33: an explosion fells the trees and shatters the boulders in its reach, the pieces flung away from it.
const Sim = preload("res://scripts/siege/siege_sim.gd")
func _init():
	var s = Sim.new()
	s.setup(4, 3)
	for u in s.units: u.bot = false; u.move = Vector2.ZERO; u.pos = Sim.spawn(u.team)
	var tree: Dictionary = s.nodes.filter(func(n): return str(n.kind) == "wood" and int(n.amount) > 0)[0]
	var stone: Dictionary = s.nodes.filter(func(n): return str(n.kind) == "stone" and int(n.amount) > 0)[0]
	var ok := true
	for n in [tree, stone]:
		var at: Vector2 = (n.p as Vector2) + Vector2(2.0, 0.0)
		var before: int = s.items.size()
		s._blast_nodes(at, Sim.BOMB_R, 7.5)
		var fresh: Array = s.items.slice(before)
		var outward := 0
		for it in fresh:
			if (it.vel as Vector2).dot((it.pos as Vector2) - at) > 0.0 and (it.vel as Vector2).length() > 3.0:
				outward += 1
		var want: int = Sim.LOGS_PER_TREE if str(n.kind) == "wood" else Sim.ROCKS_PER_BOULDER
		print("%s: amount %d, %d pieces, %d flung outward" % [n.kind, n.amount, fresh.size(), outward])
		ok = ok and int(n.amount) == 0 and fresh.size() >= want and outward == fresh.size()      # (neighbours in reach fall too)
	var far: Dictionary = s.nodes.filter(func(n): return int(n.amount) > 0 and (n.p as Vector2).distance_to(tree.p) > 20.0)[0]
	var amt: int = far.amount
	s._blast_nodes(tree.p, Sim.BOMB_R, 7.5)
	ok = ok and int(far.amount) == amt
	# 0.31.34: a catapult stone breaks them too
	var t3s: Array = s.nodes.filter(func(n): return str(n.kind) == "wood" and int(n.amount) > 0)
	var t3: Dictionary = t3s[0]
	var before3: int = s.items.size()
	s.shells.append({"id":999, "team":1, "from":Vector2(0, -40), "to":(t3.p as Vector2) + Vector2(1.0, 0.0), "t":0.0, "flight":0.2})
	var hit_at: Vector2 = (t3.p as Vector2) + Vector2(1.0, 0.0)
	for i in 12:
		s.step()
		s.drain_events()
		if s.items.size() > before3:
			break                                        # the tick it landed: the pieces' launch speeds
	var flung3: Array = s.items.slice(before3).filter(func(it): return (it.vel as Vector2).length() > 2.0 and (it.vel as Vector2).dot((it.pos as Vector2) - hit_at) > 0.0)
	print("catapult: tree amount %d, %d pieces flung" % [t3.amount, flung3.size()])
	ok = ok and int(t3.amount) == 0 and flung3.size() >= Sim.LOGS_PER_TREE
	print("BLAST_NODES_PASS" if ok else "BLAST_NODES_FAIL")
	quit(0 if ok else 1)
