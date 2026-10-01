extends SceneTree
# Fatebound trailer 2 (Round 21, Kevin: "a new cinematic trailer with the music and the herald talking through
# it ... the end will have a spectacular reveal of the name with VFX, the entire kingdom in the backdrop and the
# sun's light godraying through the title"). One shot per run, recorded with Godot's Movie Maker:
#   (override.cfg with a 1920x1080 window)  godot --rendering-method mobile --fixed-fps 30 \
#     --write-movie /tmp/trailer2/<shot>.avi --path . -s res://tools/trailer2_shots.gd       (SHOT=<shot>)
# Shots: dawn captive heroes assault rampart whirl feast carry reveal. HUD hidden. "reveal" is at golden hour
# (the sun low behind the enemy castle) and writes the sun's screen position per frame to
# /tmp/trailer2/reveal_sun.json for the god rays (tools/trailer2_edit.py).
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Castle = preload("res://scripts/siege/siege_castle.gd")
const LENGTH := {"dawn": 5.0, "clash": 4.5, "captive": 4.0, "heroes": 4.0, "lineup": 4.0, "gather": 4.0, "build": 4.5, "assault": 5.5,
	"rampart": 4.0, "whirl": 3.0, "feast": 4.0, "carry": 5.0, "throne": 4.0, "reveal": 9.0}
const SUN_DIR := Vector3(0.0, 0.16, -1.0)        # where the reveal's sun sits: low, beyond the enemy castle
var mode
var shot := "dawn"
var frames := 0
var t := 0.0
var cam_a := []
var cam_b := []
var orbit := {}
var follow := ""
var walkers := {}
var chasers := []
var beats := []
var sun_track := []

func _init() -> void:
	shot = OS.get_environment("SHOT") if OS.has_environment("SHOT") else "dawn"
	mode = Mode.new()
	root.add_child(mode)

func _v(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)

func _revive(u: Dictionary) -> void:
	u.state = "idle"
	u.max_hp = float(mode.sim.stat(u, "hp"))
	u.hp = u.max_hp
	u.respawn_at = 0.0
	u.stun = 0.0

func _sturdy(u: Dictionary) -> void:
	u.max_hp = 5000.0
	u.hp = 5000.0

func _golden_hour() -> void:
	var d := SUN_DIR.normalized()
	for l in mode.view.find_children("*", "DirectionalLight3D", true, false):
		var sun: DirectionalLight3D = l
		sun.global_transform.basis = Basis.looking_at(-d)
		sun.light_color = Color("#ffc98a")
		sun.light_energy = 1.25
		sun.light_angular_distance = 2.5
	for w in mode.view.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (w as WorldEnvironment).environment
		var sm := env.sky.sky_material as ProceduralSkyMaterial
		if sm != null:
			sm.sky_top_color = Color("#4d6fa8")
			sm.sky_horizon_color = Color("#ffb877")
			sm.ground_horizon_color = Color("#f6bf8c")
			sm.ground_bottom_color = Color("#f6bf8c")
			sm.sun_angle_max = 40.0
			sm.sun_curve = 0.08
		env.fog_light_color = Color("#f2c192")

func _stage() -> void:
	var s = mode.sim
	var me: Dictionary = s.by_id[mode.hud.player_id]
	mode.hud.visible = false
	mode.hud.diag = null
	for u in s.units:
		_revive(u)
		u.bot = true
	match shot:
		"dawn":
			for i in int(60.0 / Sim.TICK):
				s.step(Sim.TICK)
				s.drain_events()
			cam_a = [Vector3(-34, 30, 96), Vector3(0, 4, 5)]
			cam_b = [Vector3(-14, 19, 64), Vector3(0, 2, 18)]
		"captive":
			# Our King behind bars in THEIR dungeon, their guards at the bars.
			var cell: Vector2 = Sim.cell(0)
			var jail: Dictionary = s.gates.filter(func(g): return g.team == 1 and str(g.get("kind", "")) == "jail")[0]
			var out: Vector2 = ((jail.c as Vector2) - cell).normalized()
			var side := Vector2(out.y, -out.x)
			var k := 0
			for u in s.units:
				if u.team == 1 and k < 3:
					u.bot = false
					u.move = Vector2.ZERO
					u.pos = (jail.c as Vector2) + out * 1.6 + side * (-1.6 + k * 1.6)
					u.face = Sim.angle_of(cell - (u.pos as Vector2))
					k += 1
			var cy := Sim.height_at(cell)
			cam_a = [_v(cell + out * 7.0 + side * 2.5, cy + 6.5), _v(cell, cy + 1.0)]
			cam_b = [_v(cell + out * 3.6 + side * 1.2, cy + 2.8), _v(cell, cy + 1.2)]
		"heroes":
			# One villager walks up to the Barracks door and comes out a Knight -- close, so it reads.
			var st: Dictionary = s.stands.filter(func(x): return x.team == 0 and x.cls == "knight")[0]
			var door: Vector2 = st.p
			# (Not the player's unit: the match loop overwrites its move with the idle joystick.)
			var hero: Dictionary = s.units.filter(func(x): return x.team == 0 and x.id != me.id)[0]
			s._set_class(hero, "villager", false)
			hero.bot = false
			hero.pos = door + Vector2(4.5, 0.8)
			walkers[hero.id] = (door - (hero.pos as Vector2)).normalized() * 0.7
			me.pos = Sim._c(0, Vector2(6.0, 12.0))
			for u in s.units:
				if u.id != hero.id and u.id != me.id:
					u.pos = Sim.spawn(u.team) if u.team == 1 else Sim._c(0, Vector2(6.0, 12.0))
					u.bot = false
					u.move = Vector2.ZERO
			cam_a = [_v(door + Vector2(6.5, 4.8), 3.6), _v(door + Vector2(1.2, 0.4), 1.2)]
			cam_b = [_v(door + Vector2(4.2, 3.4), 2.7), _v(door + Vector2(0.6, 0.0), 1.2)]
		"lineup":
			# Every hat is a hero: the seven classes in a row, the camera sliding along them.
			var classes := ["knight", "barbarian", "rogue", "ranger", "mage", "priest", "worker"]
			var j2 := 0
			for u in s.units:
				u.bot = false
				u.move = Vector2.ZERO
				if u.team == 0 and j2 < classes.size():
					s._set_class(u, classes[j2], j2 % 2 == 0)
					u.pos = Sim._c(0, Vector2(-7.2 + j2 * 2.4, 12.2))
					u.face = Sim.angle_of(Vector2(0.0, -1.0))
					j2 += 1
				else:
					u.pos = Sim.spawn(1) if u.team == 1 else Sim._c(0, Vector2(0.0, 24.0))
			cam_a = [_v(Sim._c(0, Vector2(-8.5, 7.6)), 2.6), _v(Sim._c(0, Vector2(-3.5, 12.2)), 1.3)]
			cam_b = [_v(Sim._c(0, Vector2(8.5, 7.6)), 2.6), _v(Sim._c(0, Vector2(3.5, 12.2)), 1.3)]
		"gather":
			# The economy (Kevin: "the trailer should include gathering resources"): workers chop a tree and
			# mine a rock with their tools; one hauls lumber home.
			var best_w := {}
			var best_s := {}
			var bd := INF
			for nw in s.nodes:
				if nw.kind != "wood" or (nw.p as Vector2).y < 6.0 or (nw.p as Vector2).y > 30.0:
					continue
				for ns in s.nodes:
					if ns.kind == "stone" and (ns.p as Vector2).distance_to(nw.p) < bd:
						bd = (ns.p as Vector2).distance_to(nw.p)
						best_w = nw
						best_s = ns
			var crew: Array = s.units.filter(func(x): return x.team == 0 and x.id != me.id).slice(0, 4)
			var spots := [[best_w, Vector2(1.0, 0.3)], [best_w, Vector2(-0.9, 0.6)], [best_s, Vector2(1.0, -0.2)]]
			for k4 in 3:
				var wk: Dictionary = crew[k4]
				var node: Dictionary = spots[k4][0]
				s._set_class(wk, "worker", false)
				wk.bot = false
				wk.pos = (node.p as Vector2) + (spots[k4][1] as Vector2).normalized() * (float(node.r) + 0.75)
				wk.face = Sim.angle_of((node.p as Vector2) - (wk.pos as Vector2))
				wk.task = {"kind": "gather", "t": 99.0, "node": node.id}
			var hauler: Dictionary = crew[3]
			s._set_class(hauler, "worker", false)
			hauler.bot = false
			hauler.load = {"kind": "wood", "n": 3}
			hauler.pos = (best_w.p as Vector2) + Vector2(-3.5, -1.5)
			walkers[hauler.id] = Vector2(0.15, 1.0).normalized() * 0.55
			for u in s.units:
				if not crew.has(u):
					u.bot = false
					u.move = Vector2.ZERO
					u.pos = Sim.spawn(u.team)
			var mid2: Vector2 = ((best_w.p as Vector2) + (best_s.p as Vector2)) * 0.5
			orbit = {"c": _v(mid2, 0.9), "r": 7.5, "h": 3.6, "a0": 2.6, "a1": 3.5}
		"build":
			# Spending it: a worker raises a ladder against their wall (3 s), and a knight heads up it.
			s.stock[0].wood = 60
			var spot2 := Vector2(-14.0, -36.3)
			var builder: Dictionary = s.units.filter(func(x): return x.team == 0 and x.id != me.id)[0]
			var climber: Dictionary = s.units.filter(func(x): return x.team == 0 and x.id != me.id)[1]
			s._set_class(builder, "worker", false)
			builder.bot = false
			builder.pos = spot2
			builder.face = Sim.angle_of(Vector2(0.0, -1.0))
			s._set_class(climber, "knight", true)
			climber.bot = false
			climber.pos = spot2 + Vector2(3.4, 2.6)
			for u in s.units:
				if u.id != builder.id and u.id != climber.id:
					u.bot = false
					u.move = Vector2.ZERO
					u.pos = Sim.spawn(u.team)
			s.act(builder.id, "interact")
			# Once it's up the builder steps aside and the knight heads up it; the camera from the front-right so
			# the ladder isn't hidden behind them (standing at its foot, they hid it).
			beats = [[3.05, builder.id, "aside"], [3.2, climber.id, "climb"]]
			cam_a = [_v(spot2 + Vector2(5.5, 5.0), 3.4), _v(Vector2(-14.0, -37.6), 1.6)]
			cam_b = [_v(spot2 + Vector2(4.0, 4.2), 3.0), _v(Vector2(-14.0, -37.6), 1.9)]
		"clash":
			# Sixteen against sixteen: both armies charge into each other on our side of the river.
			var mix2 := ["knight", "barbarian", "ranger", "rogue", "mage", "priest", "knight", "barbarian"]
			var bi := 0
			var ri := 0
			for u in s.units:
				u.bot = false
				if u.team == 0:
					s._set_class(u, mix2[bi % mix2.size()], bi % 3 == 0)
					u.pos = Vector2(-13.0 + (bi % 8) * 3.6, 23.0 + (bi / 8) * 2.2)
					walkers[u.id] = Vector2(0.0, -1.0)
					bi += 1
				else:
					s._set_class(u, mix2[(ri + 3) % mix2.size()], ri % 3 == 1)
					u.pos = Vector2(-12.0 + (ri % 8) * 3.6, 9.5 - (ri / 8) * 2.2)
					walkers[u.id] = Vector2(0.0, 1.0)
					ri += 1
				_revive(u)
			beats = [[1.2, "", "melee"]]
			cam_a = [Vector3(-19.0, 3.2, 15.5), Vector3(-2.0, 1.2, 16.0)]
			cam_b = [Vector3(-12.0, 4.6, 12.0), Vector3(4.0, 1.2, 16.5)]
		"throne":
			# The last steps: a knight carries our King into the throne room and sets him down -- a rescue.
			var o2: Dictionary = s.oracles[0]
			var bearer: Dictionary = s.units.filter(func(x): return x.team == 0 and x.id != me.id)[0]
			s._set_class(bearer, "knight", true)
			bearer.bot = false
			bearer.pos = (o2.pos as Vector2) + Vector2(0.5, 0.0)
			s.act(bearer.id, "interact")
			var th: Vector2 = Sim.throne(0)
			var start2: Vector2 = Sim._c(0, Vector2(0.0, 24.2))
			bearer.pos = start2
			o2.pos = start2
			walkers[bearer.id] = (th - start2).normalized()
			# Four allies flank the throne (none between the camera and it); the rest far away.
			var flank := [Vector2(-3.2, 26.2), Vector2(-2.2, 27.4), Vector2(2.4, 27.2), Vector2(3.4, 26.0)]
			var fi := 0
			for u in s.units:
				if u.id != bearer.id:
					u.bot = false
					u.move = Vector2.ZERO
					if u.team == 0 and u.id != me.id and fi < flank.size():
						u.pos = Sim._c(0, flank[fi])
						fi += 1
					else:
						u.pos = Sim.spawn(u.team)
					u.face = Sim.angle_of(th - (u.pos as Vector2))
			var thy := Sim.height_at(th)
			cam_a = [_v(Sim._c(0, Vector2(5.5, 21.0)), thy + 4.2), _v(th + (start2 - th) * 0.5, thy + 1.0)]
			cam_b = [_v(Sim._c(0, Vector2(3.5, 22.6)), thy + 3.2), _v(th, thy + 1.2)]
		"assault":
			var eg: Dictionary = s.gates.filter(func(g): return g.team == 1 and str(g.get("kind", "")) != "jail")[0]
			var front: Vector2 = Sim.gate_front(eg)
			var out2: Vector2 = (front - (eg.c as Vector2)).normalized()
			var side2 := Vector2(out2.y, -out2.x)
			var mix := ["knight", "barbarian", "ranger", "mage", "priest", "knight"]
			var b := 0
			var r := 0
			for u in s.units:
				if u.team == 0 and b < 12:
					s._set_class(u, mix[b % mix.size()], b % 3 == 0)
					u.pos = front + out2 * (3.0 + (b % 3) * 2.2) + side2 * ((b / 3) * 2.4 - 3.6)
					b += 1
				elif u.team == 1 and r < 10:
					s._set_class(u, ["ranger", "rogue", "ranger", "barbarian"][r % 4], r % 4 == 0)
					u.pos = front + out2 * (0.6 + (r % 2) * 1.2) + side2 * ((r / 2) * 2.0 - 4.0)
					r += 1
				_revive(u)
			orbit = {"c": _v(front + out2 * 2.0, 0.8), "r": 13.0, "h": 8.5, "a0": Sim.angle_of(out2) - 0.9, "a1": Sim.angle_of(out2) + 0.5}
		"rampart":
			# Rangers on our rampart loose volleys over the wall at the attackers below.
			var posts: Array = Castle.RAMPART_POSTS
			var a := 0
			var e := 0
			for u in s.units:
				if u.team == 0 and a < posts.size():
					s._set_class(u, "ranger", a % 2 == 0)
					u.role = "defend"
					u.pos = Sim._c(0, posts[a])
					u["post"] = a
					_sturdy(u)
					a += 1
				elif u.team == 0:
					u.pos = Sim._c(0, Vector2(0.0, 24.0))
					u.bot = false
				elif u.team == 1 and e < 9:
					s._set_class(u, ["knight", "barbarian", "rogue"][e % 3], false)
					u.pos = Sim._c(0, Vector2(-6.0 + (e % 5) * 3.0, -5.0 - (e / 5) * 3.0))
					_sturdy(u)
					e += 1
			for i in int(1.0 / Sim.TICK):
				s.step(Sim.TICK)
			var eye0: Vector2 = Sim._c(0, Vector2(7.5, 8.5))
			var eye1: Vector2 = Sim._c(0, Vector2(5.0, 7.0))
			cam_a = [_v(eye0, 6.5), _v(Sim._c(0, Vector2(0.0, -6.0)), 0.8)]
			cam_b = [_v(eye1, 5.2), _v(Sim._c(0, Vector2(-1.0, -7.0)), 0.8)]
		"whirl":
			var field := Vector2(-6.0, 16.0)
			s._set_class(me, "barbarian", true)
			me.bot = false
			me.pos = field
			me.cd_ability = 0.0
			var foes := 0
			for u in s.units:
				if u.team == 1 and foes < 6:
					u.bot = false
					u.move = Vector2.ZERO
					s._set_class(u, ["knight", "rogue", "barbarian", "ranger", "mage", "rogue"][foes], false)
					u.pos = field + Vector2(cos(foes * 1.05 + 0.3) * 2.1, sin(foes * 1.05 + 0.3) * 2.1)
					_sturdy(u)
					foes += 1
				elif u.team == 0 and u.id != me.id:
					u.pos = Sim.spawn(0)
			s.act(me.id, "ability")
			orbit = {"c": _v(field, 1.0), "r": 6.5, "h": 3.4, "a0": 0.4, "a1": 2.2}
		"feast":
			# A rogue walks a fish into our dungeon (the cell door lifts for friends) and feeds THEIR King:
			# he goes from fatter to fattest, with a puff.
			var cap: Dictionary = s.oracles[1]
			cap.cakes = 11
			cap.weight = 3
			var jail2: Dictionary = s.gates.filter(func(g): return g.team == 0 and str(g.get("kind", "")) == "jail")[0]
			var out3: Vector2 = ((jail2.c as Vector2) - (cap.pos as Vector2)).normalized()
			var feeder: Dictionary = s.units.filter(func(x): return x.team == 0 and x.id != me.id)[0]
			s._set_class(feeder, "rogue", false)
			feeder.bot = false
			feeder.offering = true
			feeder.pos = (jail2.c as Vector2) + out3 * 2.2
			walkers[feeder.id] = -out3 * 0.6
			beats = [[1.9, feeder.id, "feed"]]
			for u in s.units:
				if u.id != feeder.id:
					u.pos = Sim.spawn(u.team)
					u.bot = false
					u.move = Vector2.ZERO
			var cy2 := Sim.height_at(cap.pos)
			var side3 := Vector2(out3.y, -out3.x)
			cam_a = [_v((cap.pos as Vector2) + out3 * 6.0 + side3 * 3.0, cy2 + 4.6), _v(cap.pos, cy2 + 1.2)]
			cam_b = [_v((cap.pos as Vector2) + out3 * 3.8 + side3 * 1.8, cy2 + 3.0), _v(cap.pos, cy2 + 1.4)]
		"carry":
			var start := Vector2(0.0, -9.0)
			var home_dir := Vector2(0.0, 1.0)
			var allies: Array = s.units.filter(func(x): return x.team == 0 and x.id != me.id)
			var foes2: Array = s.units.filter(func(x): return x.team == 1)
			var carrier: Dictionary = allies[0]
			s._set_class(carrier, "knight", true)
			var o: Dictionary = s.oracles[0]
			carrier.bot = false
			carrier.pos = o.pos + Vector2(0.5, 0)
			s.act(carrier.id, "interact")
			carrier.pos = start
			o.pos = start
			walkers[carrier.id] = home_dir
			for k2 in 3:
				var es: Dictionary = allies[k2 + 1]
				s._set_class(es, ["barbarian", "priest", "ranger"][k2], k2 == 0)
				es.bot = false
				es.pos = start + Vector2([-1.6, 1.6, 0.0][k2], [-0.6, -0.6, -2.0][k2])
				walkers[es.id] = home_dir
			for k3 in 4:
				var fo: Dictionary = foes2[k3]
				s._set_class(fo, ["rogue", "knight", "barbarian", "rogue"][k3], false)
				fo.bot = false
				fo.pos = start + Vector2(-2.0 + k3 * 1.4, -7.5 - (k3 % 2) * 1.2)
				chasers.append(fo.id)
			me.pos = Sim.spawn(0)
			follow = carrier.id
			cam_a = [Vector3(6.5, 6.0, -6.0), Vector3(0, 1.0, 2.0)]
			cam_b = [Vector3(3.5, 7.5, -9.0), Vector3(0, 1.0, 3.5)]
		"reveal":
			# The whole kingdom at golden hour, the sun low beyond the enemy castle; the title and its god
			# rays are composited over this in post.
			for i in int(40.0 / Sim.TICK):
				s.step(Sim.TICK)
				s.drain_events()
			_golden_hour()
			cam_a = [Vector3(0.0, 24.0, 90.0), Vector3(0.0, 9.0, -40.0)]
			cam_b = [Vector3(0.0, 33.0, 104.0), Vector3(0.0, 12.0, -40.0)]
	mode.view.snap_camera()

func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)

func _process(delta: float) -> bool:
	frames += 1
	mode._guard_clock = -1.0e9
	if frames == 2:
		_stage()
	if frames < 2:
		return false
	t += delta
	var e := _ease(clampf(t / float(LENGTH[shot]), 0.0, 1.0))
	var s = mode.sim
	if not orbit.is_empty():
		var ang: float = lerpf(orbit.a0, orbit.a1, e)
		var c: Vector3 = orbit.c
		mode.view.cam_override = [c + Vector3(sin(ang) * orbit.r, orbit.h, cos(ang) * orbit.r), c]
	elif follow != "":
		var fu: Dictionary = s.by_id[follow]
		var fp := Vector3(fu.pos.x, Sim.height_at(fu.pos), fu.pos.y)
		mode.view.cam_override = [fp + (cam_a[0] as Vector3).lerp(cam_b[0], e), fp + (cam_a[1] as Vector3).lerp(cam_b[1], e)]
	elif not cam_a.is_empty():
		mode.view.cam_override = [(cam_a[0] as Vector3).lerp(cam_b[0], e), (cam_a[1] as Vector3).lerp(cam_b[1], e)]
	for id in walkers:
		s.by_id[id].move = walkers[id]
	if follow != "":
		for id in chasers:
			var ch: Dictionary = s.by_id[id]
			ch.move = ((s.by_id[follow].pos as Vector2) - (ch.pos as Vector2)).normalized()
	for b in beats.duplicate():
		if t >= float(b[0]) and str(b[2]) == "melee":
			beats.erase(b)
			walkers.clear()
			for u in s.units:
				u.bot = true
			continue
		if t >= float(b[0]):
			beats.erase(b)
			var bu: Dictionary = s.by_id[b[1]]
			walkers.erase(b[1])
			bu.move = Vector2.ZERO
			if str(b[2]) == "feed":
				s.act(bu.id, "interact")
			elif str(b[2]) == "aside":
				walkers[bu.id] = Vector2(-1.0, 0.35).normalized() * 0.6
			elif str(b[2]) == "climb":
				walkers[bu.id] = ((Vector2(-14.0, -38.0)) - (bu.pos as Vector2)).normalized()
	if shot == "throne" and int(s.score[0]) > 0 and not has_meta("seated"):
		set_meta("seated", true)
		var ok: Dictionary = s.oracles[0]
		ok.state = "dropped"
		ok.pos = Sim.throne(0) + (Sim._c(0, Vector2(0.0, 0.0)) - Sim.throne(0)).normalized() * 0.9
		ok.carrier = ""
		ok.lifters = []
		ok.dropped_at = s.time
		walkers.clear()
		for u in s.units:
			u.move = Vector2.ZERO
	if shot == "reveal":
		var cam: Camera3D = mode.view.camera
		var sp := cam.unproject_position(cam.global_position + SUN_DIR.normalized() * 3000.0)
		var vs := root.get_visible_rect().size
		sun_track.append([sp.x / vs.x, sp.y / vs.y, not cam.is_position_behind(cam.global_position + SUN_DIR.normalized() * 3000.0)])
	if t >= float(LENGTH[shot]):
		if shot == "reveal":
			var f := FileAccess.open("/tmp/trailer2/reveal_sun.json", FileAccess.WRITE)
			f.store_string(JSON.stringify(sun_track))
			f.close()
		quit(0)
	return false
