extends SceneTree
# Fatebound: Siege trailer shots. One shot per run, recorded with Godot's Movie Maker:
#   Xvfb ... godot --rendering-method mobile --resolution 1280x720 --fixed-fps 30 \
#     --write-movie /tmp/trailer/<shot>.avi --path . -s res://tools/trailer_shots.gd   (SHOT=<shot>)
# Shots: aerial captive hats assault whirl cake carry finale. HUD hidden (cinematic); the game's own
# sound effects are recorded by the Movie Maker. Cameras ease between a start and an end pose.
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")
const LENGTH := {"aerial": 5.0, "captive": 4.0, "hats": 4.5, "assault": 6.0, "whirl": 3.5, "cake": 4.0, "carry": 5.0, "finale": 6.0}
var mode
var shot := "aerial"
var frames := 0
var t := 0.0
var cam_a := []            # [eye, target] at the start
var cam_b := []            # ... and at the end
var orbit := {}            # optional: {"c": Vector3, "r": float, "h": float, "a0": float, "a1": float}
var follow := ""           # optional: unit id the camera tracks (with cam offsets relative to it)
var hold := []             # knights holding the shield up

func _init() -> void:
	shot = OS.get_environment("SHOT") if OS.has_environment("SHOT") else "aerial"
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

func _stage() -> void:
	var s = mode.sim
	var me: Dictionary = s.by_id[mode.hud.player_id]
	mode.hud.visible = false
	mode.hud.diag = null
	for u in s.units:
		_revive(u)
		u.bot = true
	match shot:
		"aerial":
			# The war in full swing: fast-forward the bots, then glide in over the field.
			for i in int(70.0 / Sim.TICK):
				s.step(Sim.TICK)
				s.drain_events()
			# Open on the horizon (sky, mountains, the river valley), tilt down onto our castle.
			var home: Vector2 = Sim.spawn(0)
			cam_a = [Vector3(-44, 20, -34), Vector3(40, 16, 150)]
			cam_b = [Vector3(-9, 17, 22), _v(home + Vector2(0, -6), 2)]
		"captive":
			# Our Oracle, locked in their dungeon; their guards standing about.
			var cell: Vector2 = Sim.cell(0)
			var k := 0
			for u in s.units:
				if u.team == 1 and k < 3:
					u.bot = false
					u.move = Vector2.ZERO
					u.pos = cell + Vector2(-2.5 + k * 2.5, 3.2)
					u.face = Sim.angle_of(cell - (u.pos as Vector2))
					k += 1
			var cy := Sim.height_at(cell)
			cam_a = [_v(cell + Vector2(5.5, 7.5), cy + 6.0), _v(cell, cy + 0.8)]
			cam_b = [_v(cell + Vector2(2.6, 3.6), cy + 2.8), _v(cell, cy + 1.0)]
		"hats":
			# Recruits run into the hat shops and come out heroes.
			var picks := ["knight", "rogue", "mage", "barbarian"]
			var j := 0
			for u in s.units:
				if u.team == 0 and j < 4:
					s._set_class(u, "villager", false)
					u.bot = false
					var st: Dictionary = s.stands.filter(func(x): return x.team == 0 and x.cls == picks[j])[0]
					var from: Vector2 = (st.p as Vector2) + (Sim.spawn(0) - (st.p as Vector2)).normalized() * 4.5
					u.pos = from
					u.move = ((st.p as Vector2) - from).normalized() * 0.8
					j += 1
				elif u.team == 1:
					u.pos = Sim.spawn(1)
			var mid: Vector2 = Sim._c(0, Vector2(-4.0, 8.0))
			cam_a = [_v(mid + Vector2(10, -12), 13.0), _v(mid, 0.5)]
			cam_b = [_v(mid + Vector2(-2, -10), 10.0), _v(mid + Vector2(-3, 0), 0.5)]
		"assault":
			var eg: Dictionary = s.gates.filter(func(g): return g.team == 1)[0]
			var front: Vector2 = Sim.gate_front(eg)
			var out: Vector2 = (front - (eg.c as Vector2)).normalized()
			var side := Vector2(out.y, -out.x)
			var mix := ["knight", "barbarian", "ranger", "mage", "priest", "rogue"]
			var b := 0
			var r := 0
			for u in s.units:
				if u.team == 0 and b < 12:
					s._set_class(u, mix[b % mix.size()], b % 3 == 0)
					u.pos = front + out * (3.0 + (b % 3) * 2.2) + side * ((b / 3) * 2.4 - 3.6)
					b += 1
				elif u.team == 1 and r < 10:
					s._set_class(u, mix[(r + 2) % mix.size()], r % 4 == 0)
					u.pos = front + out * (0.6 + (r % 2) * 1.2) + side * ((r / 2) * 2.0 - 4.0)
					r += 1
				_revive(u)
			var c := _v(front + out * 2.0, 0.8)
			orbit = {"c": c, "r": 13.0, "h": 8.5, "a0": Sim.angle_of(out) - 0.9, "a1": Sim.angle_of(out) + 0.5}
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
					u.max_hp = 5000.0
					u.hp = 5000.0
					foes += 1
				elif u.team == 0 and u.id != me.id:
					u.pos = Sim.spawn(0)
			s.act(me.id, "ability")
			orbit = {"c": _v(field, 1.0), "r": 6.5, "h": 3.4, "a0": 0.4, "a1": 2.2}
		"cake":
			# A rogue sneaks cake to their captive, held in OUR dungeon.
			s._set_class(me, "rogue", false)
			me.bot = false
			var cap: Dictionary = s.oracles[1]
			me.pos = (cap.pos as Vector2) + Vector2(-3.0, -2.2)
			me.offering = true
			me.move = ((cap.pos as Vector2) - (me.pos as Vector2)).normalized() * 0.7
			set_meta("feed_at", 1.8)
			var cy2 := Sim.height_at(cap.pos)
			cam_a = [_v((cap.pos as Vector2) + Vector2(-5.5, -6.5), cy2 + 5.5), _v((cap.pos as Vector2) + Vector2(-1.2, -0.8), cy2 + 0.8)]
			cam_b = [_v((cap.pos as Vector2) + Vector2(-3.2, -4.0), cy2 + 3.4), _v(cap.pos, cy2 + 0.9)]
		"carry":
			# Carrying her home across the field, escorts around, the enemy on her heels.
			s._set_class(me, "knight", true)
			me.bot = false
			var o: Dictionary = s.oracles[0]
			me.pos = o.pos + Vector2(0.5, 0)
			s.act(me.id, "interact")
			var start := Vector2(-6.0, -6.0)
			me.pos = start
			o.pos = start
			me.move = Vector2(0.15, 1.0).normalized()
			var k2 := 0
			for u in s.units:
				if u.id == me.id:
					continue
				if u.team == 0 and k2 < 5:
					u.pos = start + Vector2(-2.4 + k2 * 1.2, 1.0 + (k2 % 2) * 1.6)
					k2 += 1
				elif u.team == 1 and k2 < 12:
					u.pos = start + Vector2(-4.0 + (k2 - 5) * 1.4, -6.0 - (k2 % 2) * 1.5)
					k2 += 1
			follow = me.id
			cam_a = [Vector3(7.0, 6.5, -7.0), Vector3(0, 1.0, 1.5)]      # offsets from the carrier
			cam_b = [Vector3(4.0, 8.0, -9.5), Vector3(0, 1.0, 3.0)]
		"finale":
			# Pull back from their castle for the title card.
			var eg2: Dictionary = s.gates.filter(func(g): return g.team == 1)[0]
			var c2: Vector2 = Sim.gate_front(eg2)
			# Pull back and tilt up: their castle, the mountains and the sky behind it for the title.
			cam_a = [_v(c2 + Vector2(6, 9), 9.0), _v(c2 + Vector2(0, -8), 3.0)]
			cam_b = [_v(c2 + Vector2(12, 34), 22.0), _v(c2 + Vector2(0, -90), 26.0)]
	mode.view.snap_camera()

func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)

func _process(delta: float) -> bool:
	frames += 1
	mode._guard_clock = -1.0e9                   # no heat-guard toast / resolution drop in renders
	if frames == 2:
		_stage()
	if frames < 2:
		return false
	t += delta
	var u := clampf(t / float(LENGTH[shot]), 0.0, 1.0)
	var e := _ease(u)
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
	if shot == "cake" and has_meta("feed_at") and t >= float(get_meta("feed_at")):
		remove_meta("feed_at")
		var me: Dictionary = s.by_id[mode.hud.player_id]
		me.move = Vector2.ZERO
		s.act(me.id, "interact")
	if t >= float(LENGTH[shot]):
		quit(0)
	return false
