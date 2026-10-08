extends SceneTree
# Fatebound trailer 6 -- "Anyone Can Change Fate" (Kevin: an epic cinematic trailer following a villager as the hero of a
# battle; shoved aside while the others put on helmets, villagers cowering, he finds the bomb, musters the courage, runs it
# across the battlefield like a war movie, is blown down by a wizard's meteor in slow motion, gets up, sees their gate,
# and with his allies rallying round him -- clearing his way like blockers for a running back -- throws it; the gate
# explodes, the army charges in, the title).
#
# Four long staged runs, each a continuous match with the cameras cutting between set-ups (CAMS), cut together in
# tools/trailer6_edit.py; the gold title is trailer 4's "golden" shot. One run per process, recorded by Movie Maker:
#   tools/trailer6_render.sh <run> [W H]        (court | run | fall | charge; STILL_AT=<t> for a single frame)
# Times are game seconds (slow-motion windows stretch them on screen). The hero is a team-0 Villager that is not the
# player's unit (the match loop drives that one), kept alive through everything (_sturdy).
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Land = preload("res://scripts/siege/siege_land.gd")
const Castle = preload("res://scripts/siege/siege_castle.gd")
const RUN_V := 5.16               # a bomb-carrying Villager's run (m/s)
const LENGTH := {"court": 27.5, "run": 9.5, "fall": 16.5, "charge": 15.5}
# [from, to, time scale]
const SLOW := {"fall": [[1.74, 4.1, 0.18]], "charge": [[2.30, 2.95, 0.3], [6.30, 7.62, 0.22], [7.62, 8.6, 0.4]]}
var mode
var run := "court"
var frames := 0
var t := 0.0
var s
var hero: Dictionary = {}
var cams: Array = []          # [t0, t1, {kind, ...}]
var walkers := {}             # id -> move vector (fraction of the unit's speed)
var beats: Array = []         # [t, callable]
var nudges: Array = []        # [id, t0, dur, from, to]
var escorts := {}             # id -> [forward, right] offset round the hero (charge)
var flyers := {}              # id -> true: killed by a blast here (no respawning into the scene)
var tumble: Array = []        # the dropped bomb sliding away: [t0, dur, from, to]
var still_at := -1.0

func _init() -> void:
	run = OS.get_environment("RUN") if OS.has_environment("RUN") else "court"
	if OS.has_environment("STILL_AT"):
		still_at = float(OS.get_environment("STILL_AT"))
	mode = Mode.new()
	mode.hq_gfx = true
	root.add_child(mode)

# ---------- helpers ----------
func _v(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)

func _g(p: Vector2, up := 0.0) -> Vector3:
	return Vector3(p.x, Sim.height_at(p) + up, p.y)

func _revive(u: Dictionary) -> void:
	u.state = "idle"
	u.max_hp = float(s.stat(u, "hp"))
	u.hp = u.max_hp
	u.respawn_at = 0.0
	u.stun = 0.0
	u.move = Vector2.ZERO
	u.tower = -1
	u.carrying = false
	u.task = {}

var sturdy := {}                # id -> true: topped up every frame (the bots' Armory upgrades rescale hp to the stat)

func _sturdy(u: Dictionary) -> void:
	u.max_hp = 50000.0
	u.hp = 50000.0
	sturdy[u.id] = true

func _keep_sturdy() -> void:
	for id in sturdy:
		var u: Dictionary = s.by_id[id]
		if s.alive(u) and (float(u.max_hp) < 50000.0 or float(u.hp) < 25000.0):
			u.max_hp = 50000.0
			u.hp = 50000.0

func _put(u: Dictionary, cls: String, up: bool, p: Vector2, face_to: Vector2, bot := false) -> Dictionary:
	s._set_class(u, cls, up)
	_revive(u)
	u.pos = p
	u.face = Sim.angle_of(face_to - p) if face_to != p else u.face
	u.bot = bot
	return u

func _actor(id: String) -> Dictionary:
	return mode.view.actors.get(id, {})

func _anim(id: String, clip: String, speed := 1.0, busy := 1.0) -> void:
	var a := _actor(id)
	if not a.is_empty():
		mode.view._play(a, clip, speed, busy)

var tremble := {}               # id -> [clip, at]: a held pose that shivers

func _pose(id: String, clip: String, at: float) -> void:
	tremble[id] = [clip, at]
	_pose_now(id, clip, at)

func _pose_now(id: String, clip: String, at: float) -> void:
	# Held still on one frame of a clip (a crouch, ...).
	var a := _actor(id)
	if a.is_empty() or not is_instance_valid(a.player):
		return
	var pl: AnimationPlayer = a.player
	pl.play(clip, 0.0)
	pl.seek(at, true)
	pl.pause()                                             # (paused, not speed 0: it mustn't re-pose over _cover)
	a.clip = clip
	a.busy_until = float(mode.view._time) + 999.0

# Cowering: the arms raised round the head (or the hands to the mouth) and the head ducked, posed bone by bone over a
# held crouch -- no clip has it. [upper arm, forearm] directions as (out, up, forward) in the body's frame, then the
# chest's and head's forward bend in degrees (tried out on the Meshy villager: its arms are short, its head big).
const COVER_HEAD := [Vector3(0.35, 0.8, 0.45), Vector3(-0.9, 0.2, 0.25), 15.0, 12.0]
const COVER_MOUTH := [Vector3(0.2, -0.3, 0.9), Vector3(-0.7, 0.5, 0.5), 20.0, 14.0]
var cover := {}                 # id -> COVER_*: applied after the held pose each frame

func _cover(id: String, p: Array) -> void:
	var a := _actor(id)
	if a.is_empty() or a.get("body") == null or not is_instance_valid(a.body):
		return
	var sks: Array = (a.body as Node).find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return
	var sk: Skeleton3D = sks[0]
	var F: Vector3 = (a.root as Node3D).global_transform.basis.z
	F = Vector3(F.x, 0.0, F.z).normalized()
	var u := s.by_id.get(id, {}) as Dictionary
	if not u.is_empty():
		var fd: Vector2 = Sim.dir_of(float(u.face))
		F = Vector3(fd.x, 0.0, fd.y)
	var U := Vector3.UP
	var L: Vector3 = U.cross(F).normalized()
	var to_sk: Basis = sk.global_transform.basis.orthonormalized().inverse()
	for pair in [["chest", float(p[2])], ["head", float(p[3])]]:
		var i := sk.find_bone(pair[0])
		if i < 0:
			continue
		var gp := sk.get_bone_global_pose(i)
		var nb := Basis((to_sk * L).normalized(), deg_to_rad(pair[1])) * gp.basis
		var pg := sk.get_bone_global_pose(sk.get_bone_parent(i))
		sk.set_bone_pose_rotation(i, (pg.basis.orthonormalized().inverse() * nb.orthonormalized()).get_rotation_quaternion())
		sk.force_update_all_bone_transforms()
	for side in ["l", "r"]:
		var sg := 1.0 if side == "l" else -1.0
		for c in [["upperarm." + side, "lowerarm." + side, p[0]], ["lowerarm." + side, "wrist." + side, p[1]]]:
			var i := sk.find_bone(c[0])
			var j := sk.find_bone(c[1])
			if i < 0 or j < 0:
				continue
			var gp := sk.get_bone_global_pose(i)
			var cur: Vector3 = (sk.get_bone_global_pose(j).origin - gp.origin).normalized()
			var d: Vector3 = c[2]
			var want: Vector3 = (to_sk * (L * d.x * sg + U * d.y + F * d.z)).normalized()
			var nb := Basis(Quaternion(cur, want)) * gp.basis
			var pg := sk.get_bone_global_pose(sk.get_bone_parent(i))
			sk.set_bone_pose_rotation(i, (pg.basis.orthonormalized().inverse() * nb.orthonormalized()).get_rotation_quaternion())
			sk.force_update_all_bone_transforms()

func _anim_back(id: String, clip: String, speed: float, dur: float) -> void:
	# The clip played backwards from its end (getting up = falling, reversed).
	var a := _actor(id)
	if a.is_empty() or not is_instance_valid(a.player):
		return
	var pl: AnimationPlayer = a.player
	pl.play(clip, 0.1, -speed, true)
	a.clip = clip
	a.busy_until = float(mode.view._time) + dur

func _kill(u: Dictionary, from: Vector2, speed: float, up: float, by := {}) -> void:
	# Dead with a big throw (the ragdoll flies), and kept out of the rest of the run.
	if not s.alive(u):
		return
	s._next_push = s._push_from(from, u.pos, speed, up)
	s._kill(by, u)
	u.respawn_at = INF
	flyers[u.id] = true
	walkers.erase(u.id)
	escorts.erase(u.id)

func _team(team: int, exclude := []) -> Array:
	return s.units.filter(func(x): return x.team == team and not exclude.has(x.id) and x.id != mode.hud.player_id)

func _bone(id: String, bone: String) -> Vector3:
	# A bone's world position on an actor's body (the head of a man lying on the ground, ...).
	var a := _actor(id)
	if a.is_empty():
		return Vector3.ZERO
	var base: Vector3 = (a.root as Node3D).global_position
	if a.get("body") == null or not is_instance_valid(a.body):
		return base + Vector3(0.0, 1.0, 0.0)
	var sks: Array = (a.body as Node).find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return base + Vector3(0.0, 1.0, 0.0)
	var sk: Skeleton3D = sks[0]
	var i := sk.find_bone(bone)
	return sk.global_transform * sk.get_bone_global_pose(i).origin if i >= 0 else base + Vector3(0.0, 1.0, 0.0)

func _hero_pos() -> Vector2:
	return hero.pos

func _bomb() -> Dictionary:
	return s.bombs[0]

func _beat(at: float, f: Callable) -> void:
	beats.append([at, f])

func _cam(t0: float, t1: float, spec: Dictionary) -> void:
	cams.append([t0, t1, spec])

func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

func _quiet() -> void:
	# No match music or Herald in the recording (the trailer has its own); the game's sound effects stay.
	if mode._music != null:
		mode._music.stop()
	if mode._herald != null:
		mode._herald.stop()

func _golden_hour() -> void:
	# Late afternoon, the sun low beyond the enemy castle (as trailer 4's title): long shadows, warm light.
	var d := Vector3(0.35, 0.30, -1.0).normalized()
	for l in mode.view.find_children("*", "DirectionalLight3D", true, false):
		var sun: DirectionalLight3D = l
		sun.global_transform.basis = Basis.looking_at(-d)
		sun.light_color = Color("#ffd2a0")
		sun.light_energy = 1.2
	for w in mode.view.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (w as WorldEnvironment).environment
		var sm := env.sky.sky_material as ProceduralSkyMaterial if env.sky != null else null
		if sm != null:
			sm.sky_top_color = Color("#56789f")
			sm.sky_horizon_color = Color("#f5c08c")
			sm.ground_horizon_color = Color("#efc296")
		env.fog_light_color = Color("#efc8a0")

# ---------- staging ----------
func _stage() -> void:
	s = mode.sim
	var me: Dictionary = s.by_id[mode.hud.player_id]
	mode.hud.visible = false
	mode.hud.diag = null
	s.bombs = [{}, {}]
	s.bomb_next = [INF, INF]
	for u in s.units:
		_revive(u)
		u.bot = false
		u.pos = Sim._c(u.team, Vector2(0.0, 26.0))         # parked out of sight at the back of their castle
	me.pos = Sim._c(0, Vector2(4.0, 27.0))
	var blue := _team(0)
	var red := _team(1)
	hero = blue[0]
	_sturdy(hero)
	if OS.get_environment("GOLDEN") != "0":
		_golden_hour()
	match run:
		"court": _stage_court(blue.slice(1), red)
		"run": _stage_run(blue.slice(1), red)
		"fall": _stage_fall(blue.slice(1), red)
		"charge": _stage_charge(blue.slice(1), red)
	s.drain_events()                                         # (no class-change sparks from the staging itself)
	mode.view.snap_camera()
	_collect_props()

# Props (trees, rocks, bushes, barrels) that come between the camera and what it looks at are hidden while they do
# (the cameras move: checked every frame). Only small things: castles, walls and the land stay.
var props: Array = []          # [node, ground point (Vector2), radius]

func _collect_props() -> void:
	var keep := {}
	for a in mode.view.actors.values():
		keep[a.root] = true
	# (never the gates: the bomb shot looks straight at one, and hid its doors as it came in to land)
	for gv in mode.view.gate_nodes.values():
		var parts: Array = (gv.get("doors", []) as Array).map(func(d): return d.node)
		if gv.has("door"):
			parts.append(gv.door)
		if gv.has("rubble"):
			parts.append(gv.rubble)
		for part in parts:
			var nd: Node = part
			while nd != null and nd != mode.view:
				keep[nd] = true
				nd = nd.get_parent()
	for c in mode.view.get_children():
		if not (c is Node3D) or keep.has(c) or not (c as Node3D).visible:
			continue
		var p: Vector3 = (c as Node3D).global_position
		if p.length() < 0.5:
			continue
		var box := AABB()
		var first := true
		for mi in (c as Node3D).find_children("*", "VisualInstance3D", true, false):
			var b: AABB = (mi as VisualInstance3D).global_transform * (mi as VisualInstance3D).get_aabb()
			box = b if first else box.merge(b)
			first = false
		if c is VisualInstance3D:
			var b2: AABB = (c as VisualInstance3D).global_transform * (c as VisualInstance3D).get_aabb()
			box = b2 if first else box.merge(b2)
			first = false
		if first or box.size.length() > 9.0:
			continue
		props.append([c, Vector2(box.get_center().x, box.get_center().z), maxf(box.size.x, box.size.z) * 0.5])

func _clear_view(eye: Vector3, look: Vector3, margin := 1.1) -> void:
	var e := Vector2(eye.x, eye.z)
	var ab := Vector2(look.x, look.z) - e
	var l2 := maxf(ab.length_squared(), 0.001)
	for pr in props:
		var n = pr[0]                                          # (untyped: a freed prop must not be assigned)
		if not is_instance_valid(n):
			continue
		var ap: Vector2 = (pr[1] as Vector2) - e
		var k := clampf(ap.dot(ab) / l2, 0.0, 1.0)
		var near: bool = ap.distance_to(ab * k) < float(pr[2]) + margin and k < 0.92
		n.visible = not near

# --- 1. the courtyard: hats, the shove, the cowering villagers, the bomb, out of the gate (27.5 s) ---
func _stage_court(blue: Array, red: Array) -> void:
	var kst: Dictionary = s.stands.filter(func(x): return x.team == 0 and x.cls == "knight")[0]
	var rst: Dictionary = s.stands.filter(func(x): return x.team == 0 and x.cls == "rogue")[0]
	for st in [kst, rst]:
		st.stock = 20
	var kp: Vector2 = kst.p                                  # (-14.6, 46.8)
	var rp: Vector2 = rst.p                                  # (-14.6, 52.65)
	var gate_w := Vector2(-7.0, 41.0)
	# Hats on: villagers walk into the Knight and Rogue shops, come out armed and run for the gate.
	var hat_takers := blue.slice(0, 6)
	for k in hat_takers.size():
		var u: Dictionary = hat_takers[k]
		var dst: Vector2 = kp if k % 2 == 0 else rp
		_put(u, "villager", false, dst + Vector2(4.0 + (k / 2) * 1.6, -1.0 + (k % 3) * 0.9), dst)
		var go_at := 0.3 + k * 0.45
		_beat(go_at, func(): walkers[u.id] = (dst - (u.pos as Vector2)).normalized() * 0.8)
		u["hat_dst"] = dst
		u["after_hat"] = gate_w + Vector2(randf_range(-0.6, 0.6), 0.0)
	# The shove: a Knight fresh from the shop runs straight through him, then a Barbarian clips him from the other side.
	var hp0 := Vector2(-11.8, 47.6)
	_put(hero, "villager", false, hp0 + Vector2(0.4, 1.2), kp)
	var k1: Dictionary = blue[6]
	var b1: Dictionary = blue[7]
	_put(k1, "knight", false, Vector2(-14.9, 47.0), Vector2(-7.5, 48.4))
	_put(b1, "barbarian", false, Vector2(-14.2, 51.0), Vector2(-7.2, 44.6))
	_beat(4.6, func():
		hero.pos = hp0
		hero.face = Sim.angle_of(Vector2(-7.0, 46.0) - hp0))     # watching the armed ones run out
	_beat(5.45, func(): walkers[k1.id] = (Vector2(-7.5, 48.4) - (k1.pos as Vector2)).normalized())
	_beat(6.0, func():
		_anim(hero.id, "g/Hit_A", 1.1, 0.7)
		nudges.append([hero.id, t, 0.35, hero.pos, (hero.pos as Vector2) + Vector2(0.15, 0.85)])
		hero.face = Sim.angle_of(Vector2(-7.5, 48.4) - (hero.pos as Vector2)))
	_beat(6.95, func(): walkers[b1.id] = (Vector2(-7.2, 44.6) - (b1.pos as Vector2)).normalized())
	_beat(7.75, func():
		_anim(hero.id, "g/Hit_B", 1.1, 0.8)
		nudges.append([hero.id, t, 0.35, hero.pos, (hero.pos as Vector2) + Vector2(0.45, -0.5)])
		hero.face = Sim.angle_of(Vector2(-7.2, 44.6) - (hero.pos as Vector2)))
	_beat(9.0, func():
		walkers.erase(k1.id)
		walkers.erase(b1.id))
	# The cowering villagers behind the fountain (world (-6, 53.75)): crouched and shaking, facing the camera.
	var cower := blue.slice(8, 11)
	var cpos := [Vector2(-7.4, 53.5), Vector2(-4.0, 53.7), Vector2(-3.1, 53.1)]
	for k in cower.size():
		_put(cower[k], "villager", false, cpos[k], Vector2(-5.4 + (k - 1) * 1.6, 49.0))     # (facing the camera: their faces)
	var looks := [COVER_HEAD, COVER_MOUTH, COVER_HEAD]
	_beat(0.2, func():
		for k in cower.size():
			_pose(cower[k].id, "mb/Jump_Land", 0.15)
			cover[cower[k].id] = looks[k])
	_beat(11.6, func():                                 # a far-off blast: they duck lower
		for k in cower.size():
			var p: Array = (looks[k] as Array).duplicate()
			p[2] = float(p[2]) + 12.0
			p[3] = float(p[3]) + 16.0
			cover[cower[k].id] = p)
	_beat(12.4, func():
		for k in cower.size():
			cover[cower[k].id] = looks[k])
	# The bomb, ready by the workshop.
	var bs: Vector2 = s.bomb_spot(0)
	s.bombs[0] = {"id":0, "team":0, "state":"ready", "p":bs, "h":0.0, "carrier":"", "by":"", "from":Vector2.ZERO,
		"to":Vector2.ZERO, "t0":0.0, "lit_at":-1.0, "bot_claim":hero.id}     # (no bot runs off with it first)
	var look_from := bs + Vector2(-2.6, -1.4)                 # where he stands, looking at it
	_beat(14.0, func():
		hero.pos = look_from
		hero.face = Sim.angle_of(bs - look_from)
		walkers.erase(hero.id))
	_beat(18.3, func(): hero.face = Sim.angle_of(Vector2(-6.0, 55.5) - (hero.pos as Vector2)))   # back at them...
	_beat(19.3, func(): hero.face = Sim.angle_of(bs - (hero.pos as Vector2)))                   # ...and the bomb
	_beat(20.2, func(): walkers[hero.id] = (bs - (hero.pos as Vector2)).normalized() * 0.45)
	_beat(20.9, func():
		walkers.erase(hero.id)
		hero.move = Vector2.ZERO
		_anim(hero.id, "g/PickUp", 1.0, 1.1))
	_beat(21.45, func(): s.act(hero.id, "interact"))
	var gate_e := Vector2(7.0, 44.0)
	_beat(22.4, func(): hero.face = Sim.angle_of(gate_e - (hero.pos as Vector2)))
	_beat(23.2, func(): walkers[hero.id] = (Vector2(7.2, 38.0) - (hero.pos as Vector2)).normalized())
	_beat(24.6, func(): walkers[hero.id] = Vector2(-0.1, -1.0).normalized())
	# Out of the east gate: the battle in front of it.
	var foes := red.slice(0, 8)
	var ours := blue.slice(11, 15)
	for k in foes.size():
		_put(foes[k], ["knight", "barbarian", "rogue", "knight", "ranger", "barbarian", "knight", "mage"][k], k % 3 == 0,
			Vector2(-2.0 + (k % 4) * 4.5, 27.0 - (k / 4) * 3.0), Vector2(4.0, 40.0), true)
		_sturdy(foes[k])
	for k in ours.size():
		_put(ours[k], ["knight", "barbarian", "knight", "ranger"][k], k == 0, Vector2(0.0 + k * 4.0, 31.5), Vector2(4.0, 24.0), true)
		_sturdy(ours[k])
	# Cameras.
	_cam(0.0, 4.6, {"kind":"world", "e0":Vector3(-4.0, 13.0, 59.0), "l0":Vector3(-13.0, 1.0, 49.0),
		"e1":Vector3(-7.0, 4.2, 54.5), "l1":Vector3(-13.6, 1.4, 49.0)})
	_cam(4.6, 9.6, {"kind":"world", "e0":Vector3(-7.9, 1.55, 46.9), "l0":Vector3(-11.8, 1.3, 47.8),
		"e1":Vector3(-8.3, 1.5, 47.0), "l1":Vector3(-11.6, 1.35, 47.6), "shake":0.03})
	_cam(9.6, 14.0, {"kind":"world", "e0":Vector3(-5.4, 1.2, 49.2), "l0":Vector3(-5.4, 0.7, 53.4),
		"e1":Vector3(-5.45, 1.05, 50.0), "l1":Vector3(-5.4, 0.7, 53.4)})
	_cam(14.0, 17.0, {"kind":"world", "e0":_g(bs + Vector2(-2.0, 2.8), 1.1), "l0":_g(bs, 0.35),
		"e1":_g(bs + Vector2(-0.9, 1.3), 0.6), "l1":_g(bs, 0.3)})
	var face_dir: Vector2 = (bs - look_from).normalized()
	_cam(17.0, 20.2, {"kind":"world", "e0":_g(look_from + face_dir * 1.9, 1.75), "l0":_g(look_from, 1.6),
		"e1":_g(look_from + face_dir * 1.35, 1.7), "l1":_g(look_from, 1.62)})
	_cam(20.2, 23.2, {"kind":"world", "e0":_g(bs + Vector2(-0.6, -4.8), 2.0), "l0":_g(bs + Vector2(-1.3, 0.2), 1.1),
		"e1":_g(bs + Vector2(-0.4, -4.4), 1.9), "l1":_g(bs + Vector2(-1.2, -0.2), 1.2)})
	_cam(23.2, 27.5, {"kind":"follow", "id":hero.id, "e0":Vector3(0.25, 1.7, 3.4), "l0":Vector3(-0.1, 1.4, -4.0),
		"e1":Vector3(0.3, 1.8, 3.0), "l1":Vector3(-0.1, 1.2, -5.0), "shake":0.05})

# --- 2. the run: across our half under arrows, war-movie tracking (9.5 s) ---
func _stage_run(blue: Array, red: Array) -> void:
	var start := Vector2(9.0, 34.0)
	var dir := Vector2(0.42, -0.91).normalized()
	_put(hero, "villager", false, start, start + dir)
	s.bombs[0] = {"id":0, "team":0, "state":"carried", "p":start, "h":1.9, "carrier":hero.id, "by":"",
		"from":Vector2.ZERO, "to":Vector2.ZERO, "t0":0.0, "lit_at":-1.0}
	hero["bomb_held"] = true
	walkers[hero.id] = dir
	# Skirmishes along the way, and archers on both sides loosing over his head.
	var mix := ["knight", "barbarian", "knight", "rogue", "barbarian", "knight"]
	var spots := [Vector2(15.5, 28.0), Vector2(21.5, 17.5), Vector2(7.5, 21.0)]
	var bi := 0
	var ri := 0
	for k in spots.size():
		var c: Vector2 = spots[k]
		for j in 3:
			var a: Dictionary = blue[bi]
			_put(a, mix[(bi + j) % mix.size()], bi % 4 == 0, c + Vector2(-1.4 + j * 1.4, 0.8), c + Vector2(0, -2), true)
			_sturdy(a)
			bi += 1
			var e: Dictionary = red[ri]
			_put(e, mix[(ri + 2) % mix.size()], ri % 4 == 1, c + Vector2(-1.2 + j * 1.4, -1.0), c + Vector2(0, 2), true)
			_sturdy(e)
			ri += 1
	for k in 3:                                              # their archers, out ahead
		var e: Dictionary = red[ri]
		_put(e, "ranger", k == 1, Vector2(22.0 + k * 3.0, 9.0 + k * 1.5), Vector2(15.0, 22.0), true)
		_sturdy(e)
		ri += 1
	for k in 3:                                              # ours, behind him
		var a: Dictionary = blue[bi]
		_put(a, "ranger", k == 0, Vector2(3.0 + k * 2.5, 37.0), Vector2(20.0, 12.0), true)
		_sturdy(a)
		bi += 1
	# Two of ours running the same way beside him (the arrows aimed at them land round him).
	for k in 2:
		var a: Dictionary = blue[bi]
		_put(a, ["knight", "barbarian"][k], false, start + Vector2(3.2, 1.6) if k == 0 else start + Vector2(-2.8, 2.6), start + dir * 5.0)
		walkers[a.id] = dir * 0.93
		bi += 1
	for k in 6:
		_beat(0.4 + k * 1.3, func():
			for u in s.units:
				if u.cls == "ranger" and u.bot and s.alive(u):
					u.cd_ability = 0.0
					s.act(u.id, "ability"))
	var side := Vector2(dir.y, -dir.x)                        # his left
	var off_side := _v(side * 4.6 + dir * 0.6, 1.7)
	_cam(0.0, 4.8, {"kind":"follow", "id":hero.id, "e0":off_side, "l0":_v(dir * 1.0, 1.25),
		"e1":_v(side * 4.2 + dir * 1.6, 1.6), "l1":_v(dir * 2.0, 1.2), "shake":0.06})
	_cam(4.8, 9.5, {"kind":"follow", "id":hero.id, "e0":_v(dir * 5.2 + side * 0.7, 1.75), "l0":_v(Vector2.ZERO, 1.2),     # (down the bridge's middle, over its posts)
		"e1":_v(dir * 4.4 + side * 0.6, 1.65), "l1":_v(Vector2.ZERO, 1.25), "shake":0.07})

# --- 3. the fall: the meteor, the ringing, getting up, their gate, the bomb again (16.5 s) ---
func _stage_fall(blue: Array, red: Array) -> void:
	var h0 := Vector2(18.6, -10.8)
	var gate_front: Vector2 = Sim.gate_front(s.gates.filter(func(g): return g.team == 1 and str(g.get("kind", "")) != "jail" and (g.c as Vector2).x > 0.0)[0])
	var dir: Vector2 = (gate_front + Vector2(0.0, 9.0) - h0).normalized()
	_put(hero, "villager", false, h0, h0 + dir)
	s.bombs[0] = {"id":0, "team":0, "state":"carried", "p":h0, "h":1.9, "carrier":hero.id, "by":"",
		"from":Vector2.ZERO, "to":Vector2.ZERO, "t0":0.0, "lit_at":-1.0}
	hero["bomb_held"] = true
	walkers[hero.id] = dir
	var hit_hero: Vector2 = h0 + dir * 4.4 * 1.8                # where he is when it lands
	var side := Vector2(dir.y, -dir.x)
	var c: Vector2 = hit_hero + dir * 3.4 + side * 1.8         # the meteor: ~4 m ahead of him, on his allies
	var group := []
	var gcls := ["knight", "barbarian", "knight", "ranger", "barbarian"]
	for k in 5:
		var a: Dictionary = blue[k]
		var gp: Vector2 = c + Vector2(cos(k * 1.26), sin(k * 1.26)) * (0.6 + (k % 2) * 0.9)
		_put(a, gcls[k], k == 0, gp, c + dir * 3.0)
		group.append(a)
	var foes := []
	for k in 3:
		var e: Dictionary = red[k]
		_put(e, ["knight", "rogue", "barbarian"][k], false, c + dir * 3.5 + side * (-1.4 + k * 1.4), c, false)
		_sturdy(e)
		foes.append(e)
	# They trade blows until it lands.
	for k in 4:
		_beat(0.2 + k * 0.45, func():
			for x in group + foes:
				if s.alive(x) and x.cls != "ranger":
					x.cd_attack = 0.0
					s._start_attack(x, "attack", true))
	var mage: Dictionary = red[3]
	_put(mage, "mage", true, c + dir * 6.5 - side * 9.0, c, false)        # (well off the line to their gate: the POV)
	_sturdy(mage)
	_beat(0.75, func():
		_anim(mage.id, "r/Ranged_Magic_Summon", 1.0, 1.2)
		s.meteors.append({"team":1, "owner":mage.id, "at":c, "t_hit":s.time + 1.0, "dmg":0.0, "burn_until":-1.0})
		s._event("meteor_warn", {"id":mage.id, "team":1, "pos":c, "delay":1.0}))
	set_meta("meteor_c", c)
	set_meta("meteor_group", group)
	# The blast takes him off his feet: down on his back, the bomb rolling away.
	_beat(1.76, func():
		walkers.erase(hero.id)
		hero.move = Vector2.ZERO
		var away: Vector2 = ((hero.pos as Vector2) - c).normalized()
		hero.face = Sim.angle_of(-away)
		_anim(hero.id, "g/Death_A", 1.0, 9.0)
		nudges.append([hero.id, t, 0.55, hero.pos, (hero.pos as Vector2) + away * 1.6])
		s._drop_bomb(hero)
		var bp: Vector2 = hero.pos
		tumble = [t, 0.9, bp, bp + away.rotated(0.9) * 2.3]
		for f in foes:                                       # their soldiers scatter: off to the sides, out of his view
			var sg := 1.0 if side.dot((f.pos as Vector2) - c) >= 0.0 else -1.0
			walkers[f.id] = (side * sg + dir * 0.25).normalized() * 0.9)
	_beat(7.0, func():
		for f in foes:
			walkers.erase(f.id)
			f.move = Vector2.ZERO)
	# A long beat on the ground; then up, slowly.
	_beat(8.4, func(): _anim_back(hero.id, "g/Death_A", 0.55, 2.4))
	_beat(10.8, func():
		hero.face = Sim.angle_of(gate_front - (hero.pos as Vector2))
		_anim(hero.id, "g/Idle_B", 1.0, 0.0))
	_beat(12.6, func():
		var b := _bomb()
		walkers[hero.id] = ((b.p as Vector2) - (hero.pos as Vector2)).normalized() * 0.5)
	_beat(13.25, func():
		walkers.erase(hero.id)
		hero.move = Vector2.ZERO
		_anim(hero.id, "g/PickUp", 1.0, 1.0))
	_beat(13.8, func(): s.act(hero.id, "interact"))
	_beat(14.5, func():
		hero.face = Sim.angle_of(gate_front - (hero.pos as Vector2))
		walkers[hero.id] = (gate_front + Vector2(0.0, 9.0) - (hero.pos as Vector2)).normalized())
	# Distant fighting in the background (towards their gate).
	var bi := 5
	var ri := 4
	for k in 3:
		var bc: Vector2 = [Vector2(-4.0, -25.0), Vector2(0.5, -31.5), Vector2(22.0, -30.0)][k]     # (off his line to their gate)
		for j in 2:
			var a: Dictionary = blue[bi]
			_put(a, ["knight", "barbarian"][j], false, bc + Vector2(j * 1.5, 1.4), bc, true)
			_sturdy(a)
			bi += 1
			var e: Dictionary = red[ri]
			_put(e, ["knight", "rogue"][j], false, bc + Vector2(j * 1.5, -1.2), bc, true)
			_sturdy(e)
			ri += 1
	set_meta("gate_front", gate_front)
	# Cameras: tracking behind him; the blast from the side (slow motion); on the ground by his head; getting up; his
	# view of their gate with a snap zoom; picking the bomb up.
	_cam(0.0, 1.74, {"kind":"follow", "id":hero.id, "e0":_v(-dir * 3.6 - side * 1.6, 2.1), "l0":_v(dir * 4.0, 1.2),
		"e1":_v(-dir * 3.2 - side * 1.8, 2.0), "l1":_v(dir * 4.5, 1.1), "shake":0.06})
	var blast_eye: Vector2 = hit_hero - side * 6.5 - dir * 1.5
	_cam(1.74, 4.1, {"kind":"world", "e0":_g(blast_eye, 2.3), "l0":_g(c - dir * 0.8, 1.4),
		"e1":_g(blast_eye + side * 0.6, 2.1), "l1":_g(c - dir * 0.6, 1.6)})
	set_meta("down_cam", true)
	_cam(4.1, 8.4, {"kind":"down"})
	_cam(8.4, 10.8, {"kind":"follow", "id":hero.id, "e0":_v(dir * 3.4 + side * 1.2, 0.5), "l0":_v(Vector2.ZERO, 1.0),
		"e1":_v(dir * 3.0 + side * 1.0, 0.9), "l1":_v(Vector2.ZERO, 1.5)})
	_cam(10.8, 12.6, {"kind":"pov", "target":_v(gate_front - Vector2(0.0, 2.0), 2.4),
		"fov":[[0.0, 52.0], [0.18, 52.0], [0.32, 13.0], [1.0, 12.0]], "clear_r":3.5})
	_cam(12.6, 16.5, {"kind":"follow", "id":hero.id, "e0":_v(-side * 3.4 - dir * 1.0, 1.0), "l0":_v(dir * 0.5, 1.0),
		"e1":_v(-side * 3.0 - dir * 2.0, 1.2), "l1":_v(dir * 2.0, 1.3), "shake":0.04})

# --- 4. the charge: allies rally, clear his way, the throw, the gate, the breach, his hat (15.5 s) ---
func _stage_charge(blue: Array, red: Array) -> void:
	var gate: Dictionary = s.gates.filter(func(g): return g.team == 1 and str(g.get("kind", "")) != "jail" and (g.c as Vector2).x > 0.0)[0]
	var gfront: Vector2 = Sim.gate_front(gate)
	gate.hp = float(gate.max_hp) * 0.45                      # battered already: the bomb finishes it
	var throw_at: Vector2 = gfront + Vector2(0.6, 8.6)
	# He reaches throw_at as the throw beat comes (RUN_V: a Villager carrying the bomb, measured 5.16 m/s).
	var dir: Vector2 = (throw_at - Vector2(18.2, -9.5)).normalized()
	var h0: Vector2 = throw_at - dir * RUN_V * 6.05
	var side := Vector2(-dir.y, dir.x)                        # his right
	_put(hero, "villager", false, h0, h0 + dir)
	s.bombs[0] = {"id":0, "team":0, "state":"carried", "p":h0, "h":1.9, "carrier":hero.id, "by":"",
		"from":Vector2.ZERO, "to":Vector2.ZERO, "t0":0.0, "lit_at":-1.0}
	hero["bomb_held"] = true
	walkers[hero.id] = dir
	set_meta("throw_at", throw_at)
	set_meta("dir", dir)
	# The rally: allies round him notice and fall in beside him, one after another.
	var crew := [["knight", false, Vector2(-2.2, 1.4), [1.3, -1.5]], ["barbarian", false, Vector2(2.6, -1.4), [1.2, 1.6]],
		["knight", true, Vector2(-3.4, -2.2), [3.0, -0.4]], ["ranger", false, Vector2(3.8, 1.2), [-0.8, 2.4]],
		["barbarian", true, Vector2(-1.4, -3.6), [2.4, 1.6]], ["knight", false, Vector2(4.6, -3.0), [-0.6, -2.6]],
		["rogue", false, Vector2(-4.4, 0.2), [-1.6, -0.6]], ["knight", false, Vector2(1.0, 3.2), [-1.9, 1.0]]]
	var allies := []
	for k in crew.size():
		var cc: Array = crew[k]
		var a: Dictionary = blue[k]
		var off: Vector2 = cc[2]
		_put(a, str(cc[0]), bool(cc[1]), h0 + dir * 2.0 + side * off.x + dir * off.y, h0, false)
		_sturdy(a)
		allies.append(a)
		_beat(0.35 + k * 0.22, func():
			a.face = Sim.angle_of((hero.pos as Vector2) - (a.pos as Vector2))
			escorts[a.id] = cc[3])
	set_meta("allies", allies.map(func(x): return x.id))
	var crusader: Dictionary = allies[2]
	var archer: Dictionary = allies[3]
	var berserker: Dictionary = allies[4]
	var shield: Dictionary = allies[0]
	# 1) a red Knight steps into his path -- the Crusader's hammer.
	var e1: Dictionary = red[0]
	var p_at_2 := h0 + dir * RUN_V * 2.4
	_put(e1, "knight", false, p_at_2 + dir * 4.0 + side * 2.6, p_at_2, false)
	_sturdy(e1)
	_beat(1.6, func(): walkers[e1.id] = ((hero.pos as Vector2) + dir * 3.0 - (e1.pos as Vector2)).normalized() * 0.9)
	_beat(2.25, func():
		escorts.erase(crusader.id)
		crusader.move = Vector2.ZERO
		crusader.face = Sim.angle_of((e1.pos as Vector2) - (crusader.pos as Vector2))
		s._throw_hammer(crusader))
	_beat(2.55, func(): _kill(e1, crusader.pos, 8.5, 6.0, crusader))
	_beat(3.3, func(): escorts[crusader.id] = [2.6, -0.2])
	# 2) a Rogue leaps at him from the left -- the Archer drops him mid-air.
	var e2: Dictionary = red[1]
	var p_at_35 := h0 + dir * RUN_V * 3.6
	_put(e2, "rogue", false, p_at_35 - side * 5.0 + dir * 1.5, p_at_35, false)
	_sturdy(e2)
	_beat(3.2, func():
		e2.face = Sim.angle_of((hero.pos as Vector2) - (e2.pos as Vector2))
		e2.cd_ability = 0.0
		s.act(e2.id, "ability"))
	_beat(3.3, func():
		archer.face = Sim.angle_of((e2.pos as Vector2) - (archer.pos as Vector2))
		archer.cd_attack = 0.0
		s._start_attack(archer, "attack", false))
	_beat(3.62, func(): _kill(e2, archer.pos, 7.0, 4.5, archer))
	# 3) three charge from the front right -- the Berserker spins through them.
	var rush := []
	var p_at_45 := h0 + dir * RUN_V * 4.6
	for k in 3:
		var e: Dictionary = red[2 + k]
		_put(e, ["knight", "barbarian", "knight"][k], false, p_at_45 + dir * 4.0 + side * (2.0 + k * 1.3), p_at_45, false)
		_sturdy(e)
		rush.append(e)
		_beat(3.9, func(): walkers[e.id] = ((hero.pos as Vector2) + dir * 2.0 - (e.pos as Vector2)).normalized())
	set_meta("rush", rush.map(func(x): return x.id))
	_beat(4.35, func():
		escorts.erase(berserker.id)
		berserker.move = Vector2.ZERO
		berserker.cd_ability = 0.0
		s.act(berserker.id, "ability"))
	_beat(5.2, func(): escorts[berserker.id] = [1.8, 1.8])
	# 4) arrows from their wall -- the Knight's shield.
	var aps := [Vector2(-4.6, 4.4), Vector2(-2.2, 6.0)]           # (left of his line: out of the boom and shield shots)
	var archers := []
	for k in aps.size():
		var e: Dictionary = red[5 + k]
		_put(e, "ranger", k == 0, gfront + aps[k], h0, false)     # (not bots: a defender walks back to its gate, and
		_sturdy(e)                                               #  the gate swings open for it before the bomb lands)
		archers.append(e)
	set_meta("archers", archers.map(func(x): return x.id))
	for k2 in 2:
		_beat(4.7 + k2 * 0.55, func():
			for e in archers:
				e.face = Sim.angle_of((hero.pos as Vector2) + dir * 2.0 - (e.pos as Vector2))
				e.cd_ability = 0.0
				e.cd_attack = 0.0
				s._start_attack(e, "ability" if k2 == 0 else "attack", k2 == 1))
	_beat(5.1, func():
		escorts[shield.id] = [2.2, 0.2]
		shield.cd_ability = 0.0)
	_beat(5.35, func(): s.act(shield.id, "block"))
	# Guards at their gate (thrown by the blast).
	var guards := []
	for k in 4:
		var e: Dictionary = red[8 + k]
		# (further than GATE_OPEN_RADIUS from the gate, so it stays shut for the bomb -- and still inside the blast)
		_put(e, ["knight", "barbarian", "knight", "rogue"][k], k == 1, gfront + Vector2([-3.4, -2.2, 2.2, 3.4][k], 2.6 + (k % 2) * 0.9), throw_at, false)
		_sturdy(e)
		guards.append(e)
	set_meta("guards", guards.map(func(x): return x.id))
	# The throw.
	_beat(6.05, func():
		walkers.erase(hero.id)
		hero.move = Vector2.ZERO
		hero.face = Sim.angle_of(gfront - (hero.pos as Vector2))
		for id in escorts:
			s.by_id[id].move = Vector2.ZERO
		escorts.clear()
		_anim(hero.id, "g/Throw", 1.0, 1.2))
	_beat(6.3, func():
		hero.face = Sim.angle_of(gfront - (hero.pos as Vector2))
		s.act(hero.id, "interact")
		var b := _bomb()
		b.lit_at = s.time + 0.92 - Sim.BOMB_FUSE)             # it goes off just after it lands
	_beat(7.0, func():
		for gid in get_meta("guards"):
			var gu: Dictionary = s.by_id[gid]
			gu.face = Sim.angle_of((_bomb().p if not _bomb().is_empty() else gfront) - (gu.pos as Vector2)))
	# The breach: everyone in; the Knight who shoved him... tosses him a hat; he puts it on and follows.
	_beat(7.7, func():                                   # the gate goes: they charge the breach (after its flash)
		for a in allies:
			if s.alive(a) and a.id != shield.id:
				walkers[a.id] = (gate.c - (a.pos as Vector2)).normalized())
	_beat(8.6, func():
		walkers[shield.id] = ((hero.pos as Vector2) + dir * 1.2 + side * 0.9 - (shield.pos as Vector2)).normalized() * 0.7)
	_beat(9.6, func():
		walkers.erase(shield.id)
		shield.move = Vector2.ZERO
		shield.face = Sim.angle_of((hero.pos as Vector2) - (shield.pos as Vector2))
		_anim(shield.id, "g/Throw", 1.0, 0.8))
	_beat(9.3, func():                                   # (the dead men's hats off the ground: only his to pick up)
		s.hats = s.hats.filter(func(h): return int(h.id) == 900))
	_beat(9.95, func():
		var hp: Vector2 = (hero.pos as Vector2) + ((shield.pos as Vector2) - (hero.pos as Vector2)).normalized() * 0.5
		s.hats.append({"id":900, "cls":"knight", "up":false, "pos":hp, "t":0.0, "vel":Vector2.ZERO})
		s._event("hat_drop", {"hat":900, "cls":"knight", "pos":hp, "team":0}))
	_beat(10.7, func():
		for i in range(s.hats.size() - 1, -1, -1):
			if int(s.hats[i].id) == 900:
				s.hats.remove_at(i)
		_anim(hero.id, "g/PickUp", 1.0, 0.9))
	_beat(11.2, func():
		s._set_class(hero, "knight", false)
		_sturdy(hero)
		s._event("hat_pick", {"id":hero.id, "cls":"knight", "team":0, "hat":900}))
	_beat(12.3, func():
		walkers[shield.id] = (gate.c - (shield.pos as Vector2)).normalized()
		walkers[hero.id] = (gate.c - (hero.pos as Vector2)).normalized())
	# The rest of the army comes up behind and pours in past him.
	var wave := blue.slice(8, 15)
	for k in wave.size():
		var w: Dictionary = wave[k]
		var wp: Vector2 = throw_at - dir * (13.0 + (k / 3) * 1.6) + side * (1.4 + (k % 3) * 1.4 + (k / 3) * 0.5)     # (on his right: behind him in the hat shot)
		_put(w, ["knight", "barbarian", "knight", "rogue", "barbarian", "knight", "ranger"][k], k % 3 == 1, w.pos, w.pos, false)
		_sturdy(w)                                          # (parked out of sight until he's done with that ground)
		_beat(9.4, func():
			w.pos = wp
			w.face = Sim.angle_of(dir))
		_beat(9.5 + (k % 3) * 0.12, func(): walkers[w.id] = ((gate.c as Vector2) - (w.pos as Vector2)).normalized())
	# Cameras.
	_cam(0.0, 2.25, {"kind":"follow", "id":hero.id, "e0":_v(-dir * 9.0 + side * 3.0, 7.0), "l0":_v(dir * 3.0, 0.8),
		"e1":_v(-dir * 6.5 + side * 2.0, 4.6), "l1":_v(dir * 4.0, 1.0), "shake":0.03})
	_cam(2.25, 3.2, {"kind":"follow", "id":hero.id, "e0":_v(dir * 6.5 + side * 2.4, 1.0), "l0":_v(dir * 2.0 + side * 1.2, 1.3),
		"e1":_v(dir * 5.6 + side * 2.6, 1.0), "l1":_v(dir * 2.2 + side * 1.4, 1.3), "shake":0.05})
	# (high behind his right, over the escorts' heads: the Rogue leaps in from the left, the Archer drops him)
	_cam(3.2, 4.3, {"kind":"follow", "id":hero.id, "e0":_v(side * 2.5 - dir * 4.5, 4.2), "l0":_v(-side * 1.8 + dir * 1.0, 0.9),
		"e1":_v(side * 2.3 - dir * 3.8, 4.0), "l1":_v(-side * 1.6 + dir * 1.4, 0.9), "shake":0.04, "clear_r":2.5})
	_cam(4.3, 5.1, {"kind":"follow", "id":hero.id, "e0":_v(dir * 7.0 - side * 3.5, 2.2), "l0":_v(dir * 2.4 + side * 2.0, 1.0),
		"e1":_v(dir * 6.4 - side * 3.6, 2.0), "l1":_v(dir * 2.6 + side * 2.4, 1.0), "shake":0.05})
	_cam(5.1, 6.05, {"kind":"follow", "id":hero.id, "e0":_v(dir * 7.5 + side * 2.5, 3.6), "l0":_v(dir * 1.2, 0.9),
		"e1":_v(dir * 6.8 + side * 2.3, 3.4), "l1":_v(dir * 1.2, 1.0), "shake":0.05})     # (high in front: the shield goes up)
	_cam(6.05, 6.55, {"kind":"world", "e0":_g(throw_at + side * 3.4 + dir * 1.2, 1.2), "l0":_g(throw_at, 1.6),
		"e1":_g(throw_at + side * 3.3 + dir * 1.4, 1.2), "l1":_g(throw_at, 1.7)})
	# The bomb in the air, followed from just behind it towards their gate (eye_off: right, up, back); it lands as this
	# ends, and goes off in the wide shot of the gate.
	_cam(6.55, 7.05, {"kind":"bomb", "eye_off":Vector3(0.0, 2.4, 3.0)})     # (over the guards' heads, between them)
	# (high behind him on a long lens, over his and his friends' heads: him small at the bottom, the gate going up)
	_cam(7.05, 9.4, {"kind":"world", "e0":_g(gfront + Vector2(1.5, 18.0), 6.2), "l0":_g(gfront + Vector2(0.0, -0.6), 1.6),
		"e1":_g(gfront + Vector2(1.4, 17.0), 6.0), "l1":_g(gfront + Vector2(0.0, -0.6), 2.0), "fov0":30.0})
	# The hat: from his front left, the shield Knight beyond him tossing it over.
	_cam(9.4, 12.4, {"kind":"follow", "id":hero.id, "e0":_v(-side * 4.0 + dir * 2.5, 1.5), "l0":_v(side * 0.5 + dir * 0.3, 1.0),
		"e1":_v(-side * 3.6 + dir * 2.3, 1.45), "l1":_v(side * 0.4 + dir * 0.3, 1.05)})
	# Everyone in through the broken gate: a slow crane up from behind them.
	_cam(12.4, 15.5, {"kind":"world", "e0":_g(throw_at - dir * 3.5 + side * 1.2, 3.3), "l0":_g(gfront + dir * 2.0, 1.4),
		"e1":_g(throw_at - dir * 5.0 + side * 1.5, 5.4), "l1":_g(gfront + dir * 3.0, 1.1)})

# ---------- per frame ----------
func _slow(tt: float) -> float:
	for w in SLOW.get(run, []):
		if tt >= float(w[0]) and tt < float(w[1]):
			return float(w[2])
	return 1.0

func _shake(amount: float) -> Vector3:
	return Vector3(sin(t * 7.3) + 0.5 * sin(t * 17.9 + 1.3), 0.6 * sin(t * 9.1 + 0.7) + 0.3 * sin(t * 23.0), cos(t * 6.1 + 2.1)) * amount

func _apply_cam() -> void:
	var seg: Array = []
	for c in cams:
		if t >= float(c[0]) and t < float(c[1]):
			seg = c
	if seg.is_empty():
		seg = cams[cams.size() - 1]
	var spec: Dictionary = seg[2]
	var u := _ease((t - float(seg[0])) / maxf(0.001, float(seg[1]) - float(seg[0])))
	var eye := Vector3.ZERO
	var look := Vector3.ZERO
	var fov := float(spec.get("fov0", 52.0))
	match str(spec.kind):
		"world":
			eye = (spec.e0 as Vector3).lerp(spec.e1, u)
			look = (spec.l0 as Vector3).lerp(spec.l1, u)
		"follow":
			var a := _actor(str(spec.id))
			var base: Vector3 = (a.root as Node3D).position if not a.is_empty() else _g(s.by_id[spec.id].pos)
			eye = base + (spec.e0 as Vector3).lerp(spec.e1, u)
			look = base + (spec.l0 as Vector3).lerp(spec.l1, u)
		"down":
			# Looking down on him where he lies on his back, dazed, face up; a slow creep in. Framed on his head and
			# hips (the body as it lies, not the root it fell from): from over his chest, so his face reads upright.
			var hd := _bone(hero.id, "head")
			var hp := _bone(hero.id, "hips")
			if not has_meta("down_axis"):
				var ax := Vector2(hd.x - hp.x, hd.z - hp.z)
				set_meta("down_axis", ax.normalized() if ax.length() > 0.05 else Vector2(0.0, 1.0))
			var axis: Vector2 = get_meta("down_axis")                 # hips -> head (fixed once: no swimming)
			var gy := Sim.height_at(Vector2(hd.x, hd.z))
			var back := lerpf(1.05, 0.75, u)
			var e2 := Vector2(hd.x, hd.z) - axis * back
			eye = Vector3(e2.x, gy + lerpf(1.75, 1.3, u), e2.y)
			look = Vector3(hd.x, gy + 0.15, hd.z) + _v(axis * 0.08, 0.0)
		"pov":
			var a3 := _actor(hero.id)
			var hb3: Vector3 = (a3.root as Node3D).position
			var tg: Vector3 = spec.target
			var d3 := Vector3(tg.x - hb3.x, 0.0, tg.z - hb3.z).normalized()
			eye = hb3 + Vector3(0.0, 1.9, 0.0) - d3 * 1.3 + Vector3(d3.z, 0.0, -d3.x) * 0.95    # (his head at the edge)
			look = tg
			var ft := (t - float(seg[0])) / maxf(0.001, float(seg[1]) - float(seg[0]))
			var keys: Array = spec.fov
			fov = float(keys[keys.size() - 1][1])
			for i in keys.size() - 1:
				if ft >= float(keys[i][0]) and ft < float(keys[i + 1][0]):
					var k := (ft - float(keys[i][0])) / (float(keys[i + 1][0]) - float(keys[i][0]))
					fov = lerpf(float(keys[i][1]), float(keys[i + 1][1]), _ease(k))
		"bomb":
			var b := _bomb()
			if not b.is_empty():
				set_meta("bomb_last", _g(b.p, float(b.h) + 0.3))
			var bp: Vector3 = get_meta("bomb_last", _g(throw_target(), 1.0))
			var dir: Vector2 = get_meta("dir")
			var side := Vector2(-dir.y, dir.x)
			eye = bp + _v(side * float((spec.eye_off as Vector3).x) - dir * float((spec.eye_off as Vector3).z), float((spec.eye_off as Vector3).y))
			look = bp + _v(dir * 3.0, -0.35)
	var sh := float(spec.get("shake", 0.0))
	if sh > 0.0:
		eye += _shake(sh)
		look += _shake(sh * 0.6)
	mode.view.cam_override = [eye, look]
	mode.view.camera.fov = fov
	if not props.is_empty():
		_clear_view(eye, look, float(spec.get("clear_r", 1.1)))

func _smooth_bomb(delta: float) -> void:
	# Kevin: the bomb in the air was jittery. The sim moves it once a tick (1/30 s of game time), and in slow motion a
	# tick comes only every few frames, so it (and the camera on it) went in steps. While it flies, put it where the
	# sim's own flight curve has it at this frame's exact time -- the sim's time plus what the match loop has
	# banked towards its next tick -- and the bomb's node there too (the view would only ease towards it).
	if s == null or s.bombs.is_empty():
		return
	var b: Dictionary = s.bombs[0]
	if b.is_empty() or str(b.state) != "flying":
		return
	var tc: float = float(s.time) + float(mode._accum) + delta
	var k := clampf((tc - float(b.t0)) / Sim.BOMB_FLIGHT, 0.0, 1.0)
	b.p = (b.from as Vector2).lerp(b.to, k)
	b.h = lerpf(1.7, 0.0, k) + 3.0 * k * (1.0 - k)
	var n = mode.view.bomb_nodes[0]
	if n != null and is_instance_valid(n):
		(n as Node3D).position = Vector3(b.p.x, Sim.height_at(b.p) + float(b.h) + 0.34, b.p.y)
	if OS.has_environment("DEBUG"):
		printerr("BOMBFLY f=%d k=%.4f p=(%.3f,%.3f) h=%.3f" % [frames, k, b.p.x, b.p.y, b.h])

func throw_target() -> Vector2:
	return get_meta("throw_at") if has_meta("throw_at") else Vector2.ZERO

func _process(delta: float) -> bool:
	frames += 1
	mode._guard_clock = -1.0e9
	if frames == 2:
		_stage()
	if frames < 2:
		return false
	_quiet()
	t += delta
	if still_at >= 0.0 and frames == 3:
		t = still_at
	Engine.time_scale = _slow(t)
	_smooth_bomb(delta)
	_apply_cam()
	for b in beats.duplicate():
		if t >= float(b[0]):
			beats.erase(b)
			(b[1] as Callable).call()
	for id in walkers:
		var wu: Dictionary = s.by_id[id]
		if s.alive(wu):
			wu.move = walkers[id]
	# Escorts keep their places round him (forward, right of his heading).
	if not escorts.is_empty():
		var dir: Vector2 = get_meta("dir")
		var side := Vector2(-dir.y, dir.x)
		for id in escorts:
			var eu: Dictionary = s.by_id[id]
			if not s.alive(eu):
				continue
			var off: Array = escorts[id]
			var want: Vector2 = (hero.pos as Vector2) + dir * float(off[0]) + side * float(off[1])
			var to: Vector2 = want - (eu.pos as Vector2)
			eu.move = (dir * 0.88 + to * 0.6).limit_length(1.0)
	for n in nudges.duplicate():
		var nu: Dictionary = s.by_id[n[0]]
		var k := clampf((t - float(n[1])) / float(n[2]), 0.0, 1.0)
		nu.pos = (n[3] as Vector2).lerp(n[4], 1.0 - pow(1.0 - k, 2.0))
		if k >= 1.0:
			nudges.erase(n)
	if not tumble.is_empty():
		var b := _bomb()
		var k2 := clampf((t - float(tumble[0])) / float(tumble[1]), 0.0, 1.0)
		if not b.is_empty() and b.state == "loose":
			b.p = (tumble[2] as Vector2).lerp(tumble[3], 1.0 - pow(1.0 - k2, 2.0))
		if k2 >= 1.0:
			tumble = []
	_run_specials()
	_keep_sturdy()
	for id in tremble:
		var tr: Array = tremble[id]
		var a := _actor(id)
		if not a.is_empty() and str(a.clip) == str(tr[0]) and is_instance_valid(a.player):
			(a.player as AnimationPlayer).seek(float(tr[1]) + 0.015 * sin(t * 31.0 + float(hash(id) % 7)), true)
			if cover.has(id):
				var cp: Array = (cover[id] as Array).duplicate()
				cp[3] = float(cp[3]) + 2.5 * sin(t * 23.0 + float(hash(id) % 5))      # (the head shakes too)
				_cover(id, cp)
	if OS.has_environment("DEBUG") and run == "charge" and frames % 6 == 0 and t > 6.4 and t < 12.0:
		var g0: Dictionary = s.gates.filter(func(g): return g.team == 1 and str(g.get("kind", "")) != "jail" and (g.c as Vector2).x > 0.0)[0]
		var near := []
		for u2 in s.units:
			if s.alive(u2) and (u2.team == 1 and (u2.pos as Vector2).distance_to(g0.c) < 5.0 or u2.team == 0 and (u2.pos as Vector2).distance_to(get_meta("throw_at")) < 4.5):
				near.append("%s/%s/%s(%.1f,%.1f)%s" % [u2.team, u2.id, u2.cls, u2.pos.x, u2.pos.y, " W" if walkers.has(u2.id) else ""])
		printerr("NEAR t=%.2f open=%s broken=%s %s" % [t, g0.open, g0.broken, near])
	if OS.has_environment("DEBUG") and frames % 15 == 0:
		var db := _bomb()
		printerr("t=%.2f st=%.2f hero %s %s %s hp %.0f bomb %s" % [t, s.time, hero.pos, hero.cls, hero.state, hero.hp,
			(str(db.state) + " " + str(db.p)) if not db.is_empty() else "none"])
	if run == "court":
		_court_hats()
	if still_at >= 0.0 and frames == 7:
		root.get_texture().get_image().save_png("/tmp/trailer6/still_%s_%.1f.png" % [run, still_at])
		printerr("SHOT_DONE %s still" % run)
		quit(0)
		return false
	if t >= float(LENGTH[run]):
		printerr("SHOT_DONE %s %d frames" % [run, frames])
		quit(0)
	return false

func _court_hats() -> void:
	# Villagers reaching the shop take its hat, then run for the gate.
	for u in s.units:
		if u.has("hat_dst") and u.cls == "villager" and (u.pos as Vector2).distance_to(u.hat_dst) <= Sim.HAT_TAKE_R:
			var st: Dictionary = s.stand_near(u)
			s._set_class(u, str(st.cls) if not st.is_empty() else "knight", false)    # (no class cap in the trailer)
			if u.cls != "villager":
				walkers[u.id] = ((u.after_hat as Vector2) - (u.pos as Vector2)).normalized()
				u.erase("hat_dst")

func _run_specials() -> void:
	if run == "fall" and has_meta("meteor_c") and not has_meta("meteor_done"):
		var c: Vector2 = get_meta("meteor_c")
		for m in s.meteors:
			if (m.at as Vector2) == c and s.time + 0.04 >= float(m.t_hit):
				set_meta("meteor_done", true)
				for a in get_meta("meteor_group"):
					_kill(a, c - Vector2(0.0, 0.0), 8.5 + randf() * 2.0, 7.0 + randf() * 2.5)
	if run == "charge":
		# The Berserker's spin: each of the three it cuts is thrown, dead.
		if has_meta("rush"):
			for rid in get_meta("rush"):
				var ru: Dictionary = s.by_id[rid]
				var hk := "rhp_" + str(rid)
				var was := float(get_meta(hk, ru.hp))
				set_meta(hk, ru.hp)
				if s.alive(ru) and ru.hp < was - 1.0 and float(ru.max_hp) >= 50000.0:
					var bz: Dictionary = s.by_id[get_meta("allies")[4]]
					_kill(ru, bz.pos, 8.0, 5.5, bz)
		# The bomb: the guards go up with the gate (a bigger throw than the sim's).
		var b := _bomb()
		if not b.is_empty() and b.state == "lit" and float(b.lit_at) >= 0.0 and s.time + 0.04 >= float(b.lit_at) + Sim.BOMB_FUSE \
				and not has_meta("blown"):
			set_meta("blown", true)
			for gid in get_meta("guards"):
				var gu: Dictionary = s.by_id[gid]
				if (gu.pos as Vector2).distance_to(b.p) <= Sim.BOMB_R + 1.0:
					_kill(gu, b.p, 10.0 + randf() * 3.0, 8.5 + randf() * 3.0, hero)
			for aid in get_meta("archers"):                      # ...and their archers in front of it
				var au: Dictionary = s.by_id[aid]
				if (au.pos as Vector2).distance_to(b.p) <= 7.5:
					_kill(au, b.p, 5.5 + randf() * 1.5, 10.0 + randf() * 2.0, hero)     # (high: not into the lens)
