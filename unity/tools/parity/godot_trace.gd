extends SceneTree
# Parity trace (Unity port): runs the GDScript match sim headless and prints one digest line per tick -- the units'
# exact bits (positions as float32, health/facing/timers as float64), the projectiles and the events -- so
# simtest/ (the C# sim) can be compared tick by tick. Usage:
#   godot --headless --path godot -s unity/tools/parity/godot_trace.gd -- <seed> <hero> <ticks> [dump_tick]
# dump_tick: print every unit's full line at that tick (to find what differs).
const Sim = preload("res://scripts/siege/siege_sim.gd")

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var seed_v := int(a[0]) if a.size() > 0 else 7
	var hero := str(a[1]) if a.size() > 1 else "knight"
	if hero == "-":
		hero = ""
	var ticks := int(a[2]) if a.size() > 2 else 900
	var dump_at := int(a[3]) if a.size() > 3 else -1
	var s = Sim.new()
	s.setup(5, seed_v)
	s.setup_moba(hero, seed_v)
	print("INIT ", _digest(s, false), " ", s.units.size(), " walls=", s.walls.size(), " fills=", s.squeeze_fills)
	for tick in range(1, ticks + 1):
		if s.ended:
			print("ENDED ", tick, " ", s.winner, " ", s.end_reason)
			break
		s.step(Sim.TICK)
		var ev: Array = s.drain_events()
		var ek := []
		for e in ev:
			ek.append(str(e.k))
		print("T ", tick, " ", s.units.size(), " ", s.projectiles.size(), " ", _digest(s, tick == dump_at), " ", ",".join(ek))
	quit()

static func _f32(v: Array) -> String:
	return PackedFloat32Array(v).to_byte_array().hex_encode()

static func _f64(v: Array) -> String:
	return PackedFloat64Array(v).to_byte_array().hex_encode()

func _digest(s, dump: bool) -> String:
	var parts := PackedStringArray()
	for u in s.units:
		var line := "%s|%s|%s|%s" % [u.id, u.state, _f32([u.pos.x, u.pos.y, u.move.x, u.move.y]),
			_f64([u.hp, u.max_hp, u.face, u.t, u.cd_ability, u.stun, float(u.get("gold", 0.0)), float(u.get("xp", 0.0))])]
		parts.append(line)
		if dump:
			print("U ", line, " ", u.atk, " lvl=", u.get("level", 0), " hp=", u.hp, " pos=", u.pos)
	for p in s.projectiles:
		var pl := "P%d|%s|%s" % [p.id, p.kind, _f32([p.pos.x, p.pos.y])]
		parts.append(pl)
		if dump:
			print(pl)
	return "|".join(parts).md5_text().substr(0, 12)
