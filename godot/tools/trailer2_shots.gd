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
const LENGTH := {"dawn": 5.0, "captive": 4.0, "heroes": 4.0, "assault": 5.5, "rampart": 4.0, "whirl": 3.0,
	"feast": 4.0, "carry": 5.0, "reveal": 9.0}
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
			# Villagers stride into the Barracks and the Market and come out heroes.
			var picks := ["knight", "rogue", "knight"]
			var j := 0
			for u in s.units:
				if u.team == 0 and j < 3:
					s._set_class(u, "villager", false)
					u.bot = false
					var st: Dictionary = s.stands.filter(func(x): return x.team == 0 and x.cls == picks[j])[0]
					var from: Vector2 = (st.p as Vector2) + Vector2(4.2 + j * 0.8, (j - 1) * 0.9)
					u.pos = from
					walkers[u.id] = ((st.p as Vector2) - from).normalized() * 0.75
					j += 1
				elif u.team == 1:
					u.pos = Sim.spawn(1)
			var mid: Vector2 = Sim._c(0, Vector2(-14.0, 8.7))
			cam_a = [_v(mid + Vector2(12.0, -8.0), 10.0), _v(mid, 0.8)]
			cam_b = [_v(mid + Vector2(9.0, -4.0), 7.0), _v(mid + Vector2(-1.0, 0.5), 1.2)]
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
			s._set_class(me, "rogue", false)
			me.bot = false
			me.offering = true
			me.pos = (jail2.c as Vector2) + out3 * 2.2
			walkers[me.id] = -out3 * 0.6
			beats = [[1.9, me.id, "feed"]]
			for u in s.units:
				if u.id != me.id:
					u.pos = Sim.spawn(u.team)
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
		if t >= float(b[0]):
			beats.erase(b)
			var bu: Dictionary = s.by_id[b[1]]
			walkers.erase(b[1])
			bu.move = Vector2.ZERO
			if str(b[2]) == "feed":
				s.act(bu.id, "interact")
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
