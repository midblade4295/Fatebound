extends SceneTree
# Fatebound trailer 7 -- "Bring Him Home" (Kevin: "Make a new game trailer. I want it very cinematic. Have epic music,
# action sequences, slow motion ect. Also climactic end scene leading to the game title and use the new title graphic
# with the swinging tied up king").
#
# Short staged runs in a real match, each recorded by Movie Maker (one per process) and cut to the music in
# tools/trailer7_edit.py; the title card (the Home logo with the swinging tied-up King) is composited over the "titlebg"
# plate by tools/trailer7_finish.py. The plan is in tools/trailer7_script.md.
#   tools/trailer6_render.sh <run> [W H]   with SCRIPT=res://tools/trailer7_shots.gd OUTDIR=/tmp/trailer7
#   (STILL_AT=<t> for a single frame; UNTIL=<t> to stop early)
# Times are game seconds; SCALE keys ramp the game's speed (slow motion) -- the recordings are stretched by them.
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")
const View = preload("res://scripts/siege/siege_view.gd")

const RUNS := ["dawn", "captive", "muster", "charge", "charge2", "charge3", "hammer", "whirl", "meteor", "volley", "necro", "sniper", "rogue",
	"shield", "gate", "heist", "carry", "throne", "titlebg"]
const LENGTH := {"dawn": 13.0, "captive": 7.5, "muster": 13.0, "charge": 6.4, "charge2": 2.5, "charge3": 6.4, "hammer": 2.6, "whirl": 3.0, "meteor": 3.6,
	"volley": 3.0, "necro": 2.8, "sniper": 2.4, "rogue": 2.5, "shield": 2.4, "gate": 4.6, "heist": 8.0, "carry": 12.5,
	"throne": 3.6, "titlebg": 14.0}
# Slow motion: [game time, time scale] keys, linear between them (1.0 outside).
const CLASH_T := 2.9                  # about when the front ranks come within CLASH_GAP (charge; measured)
const CLASH_GAP := 2.6
const CLASH_HIT := 0.245             # after that: their blows land
const FREEZE_END := 0.262
const SCALE := {
	# (charge: relative to the moment the front ranks come within CLASH_GAP -- see _clash_step)
	#  the blows go up as they meet; time all but stops as they land (the music stops dead on it); B's first beat as it
	#  starts again, slowly, the front rank thrown (FREEZE_END: the impact cut starts there)
	"charge": [[0.0, 1.0], [0.18, 1.0], [0.23, 0.03], [FREEZE_END, 0.03], [0.29, 0.28], [1.1, 0.28], [1.5, 1.0]],
	"hammer": [[0.50, 1.0], [0.58, 0.22], [1.70, 0.22], [1.85, 1.0]],
	"whirl": [[0.70, 1.0], [0.80, 0.22], [2.30, 0.22], [2.45, 1.0]],
	"meteor": [[1.30, 1.0], [1.45, 0.20], [2.30, 0.20], [2.60, 1.0]],
	"volley": [[0.45, 1.0], [0.55, 0.25], [1.30, 0.25], [1.45, 1.0]],
	"necro": [[0.40, 1.0], [0.55, 0.28], [2.40, 0.28]],
	"sniper": [[0.40, 1.0], [0.50, 0.12], [1.00, 0.12], [1.20, 1.0]],
	"rogue": [[0.30, 1.0], [0.42, 0.18], [1.10, 0.18], [1.25, 1.0]],
	"shield": [[0.70, 1.0], [0.80, 0.25], [1.60, 0.25], [1.75, 1.0]],
	"gate": [[2.30, 1.0], [2.42, 0.30], [2.52, 0.12], [3.40, 0.12], [3.80, 1.0]],
	"heist": [[0.50, 1.0], [0.62, 0.16], [1.30, 0.16], [1.50, 1.0]],
	"carry": [[4.85, 1.0], [4.97, 0.2], [5.65, 0.2], [5.80, 1.0]],
	"throne": [[0.55, 1.0], [0.85, 0.35], [3.60, 0.35]],
}
var mode
var run := "dawn"
var frames := 0
var t := 0.0
var s
var cams: Array = []          # [t0, t1, {kind, ...}]
var walkers := {}             # id -> move vector (fraction of the unit's speed)
var routes := {}              # id -> [waypoints]: walked one after another, then the last direction kept
var beats: Array = []         # [t, callable]
var still_at := -1.0
var until := -1.0
var cam_seg := -1
var frame_dt := 0.0
var out_dir := "/tmp/trailer7"

func _init() -> void:
	run = OS.get_environment("RUN") if OS.has_environment("RUN") else "dawn"
	if OS.has_environment("STILL_AT"):
		still_at = float(OS.get_environment("STILL_AT"))
	if OS.has_environment("UNTIL"):
		until = float(OS.get_environment("UNTIL"))
	seed(7)                                       # (the same staging every time: charge, charge2, charge3 cut together)
	mode = Mode.new()
	mode.hq_gfx = true
	root.add_child(mode)

# ---------- helpers (as trailer 6) ----------
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
	u.lifting = -1
	u.task = {}

var sturdy := {}

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

func _kill(u: Dictionary, from: Vector2, speed: float, up: float, by := {}) -> void:
	# Dead with a big throw (the ragdoll flies), and kept out of the rest of the run.
	if not s.alive(u):
		return
	s._next_push = s._push_from(from, u.pos, speed, up)
	s._kill(by, u)
	u.respawn_at = INF
	walkers.erase(u.id)
	routes.erase(u.id)
	sturdy.erase(u.id)

func _team(team: int) -> Array:
	return s.units.filter(func(x): return x.team == team and x.id != mode.hud.player_id)

func _beat(at: float, f: Callable) -> void:
	beats.append([at, f])

func _cam(t0: float, t1: float, spec: Dictionary) -> void:
	cams.append([t0, t1, spec])

func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

func _quiet() -> void:
	if mode._music != null:
		mode._music.stop()
	if mode._herald != null:
		mode._herald.stop()

func _attack(u: Dictionary, kind := "attack", aim := true) -> void:
	u.cd_attack = 0.0
	if kind == "ability":
		u.cd_ability = 0.0
	s._start_attack(u, kind, aim)

func _bone_of(a: Dictionary, bone: String) -> Vector3:
	if a.get("body") == null or not is_instance_valid(a.body):
		return Vector3.ZERO
	var sks: Array = (a.body as Node).find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return Vector3.ZERO
	var sk: Skeleton3D = sks[0]
	var i := sk.find_bone(bone)
	return sk.global_transform * sk.get_bone_global_pose(i).origin if i >= 0 else Vector3.ZERO

func _bone(id: String, bone: String) -> Vector3:
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

# ---------- light ----------
func _golden_hour() -> void:
	# Late afternoon, the sun low beyond the enemy castle (as trailers 4 and 6): long shadows, warm light.
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

func _dungeon_dusk(lights: Array) -> void:
	# The captive King: the day almost gone (a cold blue light from above), torchlight (lights: [position, energy]).
	for l in mode.view.find_children("*", "DirectionalLight3D", true, false):
		var sun: DirectionalLight3D = l
		sun.light_color = Color("#8fa6ff")
		sun.light_energy = 0.16
	for w in mode.view.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (w as WorldEnvironment).environment
		var sm := env.sky.sky_material as ProceduralSkyMaterial if env.sky != null else null
		if sm != null:
			sm.sky_top_color = Color("#1b2440")
			sm.sky_horizon_color = Color("#3a3550")
			sm.ground_horizon_color = Color("#2a2838")
		env.ambient_light_color = Color("#5a6a9a")
		env.ambient_light_energy *= 0.3
		env.fog_light_color = Color("#2c3048")
	for spec in lights:
		var torch := OmniLight3D.new()
		torch.light_color = Color("#ff9a44")
		torch.light_energy = float(spec[1])
		torch.omni_range = float(spec[2])
		torch.shadow_enabled = true
		mode.view.add_child(torch)
		torch.global_position = spec[0]
		torch.set_meta("e0", float(spec[1]))
		torches.append(torch)

var torches: Array = []

func _flicker() -> void:
	for i in torches.size():
		var l: OmniLight3D = torches[i]
		l.light_energy = float(l.get_meta("e0")) * (1.0 + 0.14 * sin(t * 13.0 + i * 2.1) + 0.08 * sin(t * 29.0 + i))

# ---------- props in the way ----------
# Small props (trees, rocks, bushes, barrels) between the camera and what it looks at are hidden while they are.
var props: Array = []          # [node, ground point (Vector2), radius]

func _collect_props() -> void:
	var keep := {}
	for a in mode.view.actors.values():
		keep[a.root] = true
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
		var n = pr[0]
		if not is_instance_valid(n):
			continue
		var ap: Vector2 = (pr[1] as Vector2) - e
		var k := clampf(ap.dot(ab) / l2, 0.0, 1.0)
		var near: bool = ap.distance_to(ab * k) < float(pr[2]) + margin and k < 0.92
		n.visible = not near

# ---------- staging ----------
var park := [Vector2.ZERO, Vector2.ZERO]

func _stage() -> void:
	s = mode.sim
	var me: Dictionary = s.by_id[mode.hud.player_id]
	mode.hud.visible = false
	mode.hud.diag = null
	s.bombs = [{}, {}]
	s.bomb_next = [INF, INF]
	for o in s.oracles:
		o.cakes = 0
		o.weight = 0
	# Out of sight at the back corner of their own castle (the throne run uses the throne room: not there).
	park = [Sim._c(0, Vector2(-19.0, 24.0)), Sim._c(1, Vector2(-19.0, 24.0))]
	for u in s.units:
		_revive(u)
		u.bot = false
		u.pos = park[u.team] + Vector2(randf_range(-2.0, 2.0), randf_range(-1.5, 1.5))
	me.pos = park[0] + Vector2(3.0, 0.0)
	var blue := _team(0)
	var red := _team(1)
	if run != "captive":
		_golden_hour()
	call("_stage_" + run, blue, red)
	s.drain_events()
	mode.view.snap_camera()
	_collect_props()
	if mode.view._motes != null and not run in ["dawn", "titlebg"]:
		mode.view._motes.visible = false          # (pollen motes near the lens read as white blobs in close shots)

# --- the kingdom at golden hour: over our castle to theirs; low over the river towards their walls ---
func _stage_dawn(blue: Array, red: Array) -> void:
	for w in mode.view.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (w as WorldEnvironment).environment
		env.fog_depth_begin = 80.0
		env.fog_sun_scatter = 0.12
	# Far off on the field, a few bots skirmishing round the island tower (tiny: life in the picture).
	for k in 4:
		_put(blue[k], ["knight", "barbarian", "ranger", "knight"][k], false, Vector2(-6.0 + k * 3.5, 13.0), Vector2(0.0, 0.0), true)
		_put(red[k], ["knight", "rogue", "barbarian", "mage"][k], false, Vector2(-5.0 + k * 3.5, -13.0), Vector2(0.0, 0.0), true)
	_cam(0.0, 6.5, {"kind":"world", "e0":Vector3(-30.0, 31.0, 86.0), "l0":Vector3(-2.0, 0.0, -18.0),
		"e1":Vector3(-23.0, 26.0, 70.0), "l1":Vector3(0.0, 0.0, -30.0), "fov0":50.0, "lin":true})
	_cam(6.5, 13.0, {"kind":"world", "e0":Vector3(-11.5, 4.2, 15.0), "l0":Vector3(1.0, 4.0, -46.0),
		"e1":Vector3(-10.0, 4.8, 4.0), "l1":Vector3(1.0, 5.0, -48.0), "fov0":44.0, "lin":true})

# --- our King behind bars in their dungeon, at dusk, torchlit ---
func _stage_captive(blue: Array, red: Array) -> void:
	var cell: Vector2 = Sim.cell(0)
	var jail: Dictionary = s.gates.filter(func(g): return g.team == 1 and str(g.get("kind", "")) == "jail")[0]
	var out: Vector2 = ((jail.c as Vector2) - cell).normalized()
	var side := Vector2(out.y, -out.x)
	var fy := Sim.height_at(cell)
	# a torch on the cell's wall lights him from the side, the bars dark against it; a dim one outside rims the bars
	_dungeon_dusk([[_v(cell + side * 1.3 + out * 0.2, fy + 2.3), 2.4, 4.5], [_v((jail.c as Vector2) + out * 1.6 - side * 2.0, fy + 2.2), 0.9, 5.0]])
	# (no guards: a friend by the jail door swings it open, and the bars are the shot)
	set_meta("king_face", _v(cell, fy + 2.05))
	_cam(0.0, 7.5, {"kind":"world", "e0":_v(cell + out * 5.8 + side * 0.35, fy + 1.7), "l0":_v(cell, fy + 2.0),
		"e1":_v(cell + out * 4.7 + side * 0.2, fy + 1.8), "l1":_v(cell, fy + 2.1), "fov0":27.0, "lin":true, "clear_r":-1.0})

# --- the muster: our army formed up behind the gates; the gates swing open; out they pour ---
func _stage_muster(blue: Array, red: Array) -> void:
	var cls := [["knight", true], ["barbarian", true], ["knight", false], ["mage", true], ["barbarian", false], ["priest", true],
		["ranger", false], ["knight", true], ["barbarian", true], ["rogue", true], ["knight", false], ["ranger", true],
		["barbarian", false], ["mage", false]]
	# one long rank across the courtyard behind the rampart stairs (between the gates, the stairs fill the front of
	# the courtyard); each goes out by the nearer gate, round the stairs
	for k in 14:
		var u: Dictionary = blue[k]
		var x := -9.1 + k * 1.4
		var p := Vector2(x, 55.0 + (0.35 if k % 2 == 1 else 0.0))
		_put(u, str(cls[k][0]), bool(cls[k][1]), p, p + Vector2(0.0, -1.0))
		_sturdy(u)
		var gx := -7.0 if x < 0.0 else 7.0
		var gate_c := Vector2(gx, 44.0)
		var go := 3.7 + (9.1 - absf(x)) * 0.08
		var lane := clampf((x - gx) * 0.1, -0.5, 0.5)
		var side_x := gx + (-0.8 if gx < 0.0 else 0.8) + lane
		_beat(go, func(): routes[u.id] = [Vector2(side_x, 50.2), gate_c + Vector2(lane, 1.8), gate_c + Vector2(lane, -2.4),
			Vector2(gx * 1.4 + lane * 3.0, 20.0)])
	# a low dolly along the rank; behind them as they move off to the gates; outside, as they pour out
	_cam(0.0, 4.0, {"kind":"world", "e0":Vector3(-6.8, 1.0, 51.3), "l0":Vector3(-4.6, 1.9, 55.6),
		"e1":Vector3(1.2, 1.0, 51.3), "l1":Vector3(3.4, 1.9, 55.6), "fov0":44.0, "lin":true})
	_cam(4.0, 6.6, {"kind":"world", "e0":Vector3(-1.5, 3.0, 59.0), "l0":Vector3(-5.5, 1.6, 44.0),
		"e1":Vector3(-1.2, 2.8, 58.0), "l1":Vector3(-5.8, 1.7, 44.0), "fov0":50.0})
	_cam(6.6, 13.0, {"kind":"world", "e0":Vector3(11.6, 1.6, 35.0), "l0":Vector3(7.0, 2.2, 43.5),
		"e1":Vector3(12.6, 1.7, 30.5), "l1":Vector3(7.6, 2.0, 39.5), "fov0":46.0, "shake":0.02})

# --- the charge: both armies across the field into each other; time all but stops as they meet ---
func _stage_charge(blue: Array, red: Array) -> void:
	var bcls := ["knight", "barbarian", "knight", "barbarian", "knight", "rogue", "barbarian", "knight", "barbarian",
		"knight", "ranger", "mage", "priest", "ranger"]
	var rcls := ["barbarian", "knight", "knight", "barbarian", "knight", "barbarian", "rogue", "knight", "barbarian",
		"knight", "ranger", "mage", "knight", "ranger", "priest", "barbarian"]
	var front_b := []
	var front_r := []
	for k in 14:
		var u: Dictionary = blue[k]
		var row := 0 if k < 8 else 1
		var col := k if k < 8 else k - 8
		var p := Vector2(-7.0 + col * 2.0 + (1.0 if row == 1 else 0.0), 40.4 + row * 2.4)
		_put(u, bcls[k], k % 3 == 0, p, p + Vector2(0.0, -1.0))
		_sturdy(u)
		_beat(0.15 + randf() * 0.12, func(): walkers[u.id] = Vector2(0.0, -1.0))
		if row == 0:
			front_b.append(u)
	for k in 16:
		var u: Dictionary = red[k]
		var row := 0 if k < 8 else 1
		var col := k if k < 8 else k - 8
		var p := Vector2(-7.0 + col * 2.0 + (1.0 if row == 1 else 0.0) + 0.5, 9.6 - row * 2.4)
		_put(u, rcls[k], k % 3 == 1, p, p + Vector2(0.0, 1.0))
		_sturdy(u)
		_beat(0.15 + randf() * 0.12, func(): walkers[u.id] = Vector2(0.0, 1.0))
		if row == 0:
			front_r.append(u)
	set_meta("front_b", front_b.map(func(x): return x.id))
	set_meta("front_r", front_r.map(func(x): return x.id))
	# (the swing, the freeze and the impact are triggered by their distance: _clash_step)
	_beat(CLASH_T + 0.9, func():
		for u in s.units:
			if s.alive(u) and u.id != mode.hud.player_id and (u.pos as Vector2).y > 5.0 and (u.pos as Vector2).y < 45.0:
				walkers.erase(u.id)
				u.bot = true)
	# Cameras: down our line on a long lens; low in front of theirs coming on; the meeting from the side.
	_cam(0.0, 1.7, {"kind":"group", "ids":front_b.map(func(x): return x.id), "e0":Vector3(-16.0, 1.85, 1.4), "l0":Vector3(0.0, 1.15, -3.0),
		"e1":Vector3(-15.5, 1.9, -0.2), "l1":Vector3(0.5, 1.15, -4.5), "fov0":30.0, "shake":0.05, "lin":true})
	_cam(1.7, 2.45, {"kind":"group", "ids":front_r.map(func(x): return x.id), "e0":Vector3(1.6, 0.7, 4.6), "l0":Vector3(0.0, 1.5, -2.0),
		"e1":Vector3(1.5, 0.68, 4.2), "l1":Vector3(0.0, 1.6, -2.0), "fov0":40.0, "shake":0.06, "lin":true})
	var zc := 24.9
	_cam(2.45, 6.4, {"kind":"world", "e0":Vector3(-15.5, 2.3, zc - 1.2), "l0":Vector3(-1.0, 1.35, zc),
		"e1":Vector3(-15.0, 2.4, zc - 2.0), "l1":Vector3(-0.5, 1.3, zc - 0.4), "fov0":34.0, "lin":true})

# --- the same charge from two more angles (cutaways for the build): high and wide over the field; low in front of ours ---
func _stage_charge2(blue: Array, red: Array) -> void:
	_stage_charge(blue, red)
	cams.clear()
	_cam(0.0, 1.2, {"kind":"world", "e0":Vector3(-26.0, 13.0, 31.0), "l0":Vector3(1.0, 0.0, 24.0),
		"e1":Vector3(-24.0, 11.5, 28.5), "l1":Vector3(1.0, 0.5, 24.5), "fov0":48.0, "lin":true})
	var fb: Array = get_meta("front_b")
	_cam(1.2, 2.5, {"kind":"group", "ids":fb, "e0":Vector3(-1.4, 1.45, -4.8), "l0":Vector3(0.0, 1.35, 2.0),
		"e1":Vector3(-1.3, 1.4, -4.4), "l1":Vector3(0.0, 1.4, 2.0), "fov0":40.0, "shake":0.06, "lin":true})

# --- and the impact itself, close from the side: their front rank thrown back off its feet, up against the sky
#     (charge3: the same charge again, its own CLASH/RESUME times in its log) ---
func _stage_charge3(blue: Array, red: Array) -> void:
	_stage_charge(blue, red)
	cams.clear()
	_cam(0.0, 6.4, {"kind":"world", "e0":Vector3(-9.0, 1.9, 25.6), "l0":Vector3(0.0, 2.1, 21.0),
		"e1":Vector3(-8.6, 2.1, 24.8), "l1":Vector3(0.0, 2.4, 20.6), "fov0":50.0, "lin":true, "clear_r":1.5})

# --- montage ---
# The sun is low in the north (beyond their castle): a camera north of the action looking south has it front-lit; one
# looking north has it against the sun. SPOT is where a path from our west gate meets the westward one (dirt round it).
const SPOT := Vector2(-16.0, 25.5)

func _stage_hammer(blue: Array, red: Array) -> void:
	# The Crusader's hammer, end over end through three charging at him -- from the side.
	var cr := _put(blue[0], "knight", true, SPOT, SPOT + Vector2(0.0, -1.0))
	var foes := []
	for k in 3:
		var e := _put(red[k], ["barbarian", "knight", "rogue"][k], k == 0, SPOT + Vector2((k - 1) * 0.35, -5.2 - k * 1.9), SPOT)
		_sturdy(e)
		walkers[e.id] = (SPOT - (e.pos as Vector2)).normalized()
		foes.append(e)
	set_meta("rush", foes.map(func(x): return x.id))
	set_meta("striker", cr.id)
	_beat(0.42, func():
		cr.face = Sim.angle_of(Vector2(0.0, -1.0))
		s._throw_hammer(cr))
	_cam(0.0, 2.6, {"kind":"world", "e0":_g(SPOT + Vector2(-6.4, -2.6), 1.55), "l0":_g(SPOT + Vector2(0.0, -3.0), 1.35),
		"e1":_g(SPOT + Vector2(-6.0, -3.2), 1.5), "l1":_g(SPOT + Vector2(0.0, -3.6), 1.4), "fov0":46.0, "clear_r":1.5})

func _stage_whirl(blue: Array, red: Array) -> void:
	var bz := _put(blue[0], "barbarian", true, SPOT, SPOT + Vector2(0.0, -1.0))
	var rush := []
	for k in 4:
		var ang := -PI * 0.5 + (k - 1.5) * 0.8
		var e := _put(red[k], ["knight", "rogue", "knight", "barbarian"][k], false, SPOT + Vector2(cos(ang), sin(ang)) * 5.4, SPOT)
		_sturdy(e)
		walkers[e.id] = (SPOT - (e.pos as Vector2)).normalized()
		rush.append(e)
	set_meta("rush", rush.map(func(x): return x.id))
	set_meta("striker", bz.id)
	_beat(0.74, func():
		bz.cd_ability = 0.0
		s.act(bz.id, "ability"))
	_cam(0.0, 3.0, {"kind":"orbit", "c":_g(SPOT, 0.9), "r":7.6, "h":2.1, "a0":-2.1, "a1":-1.3, "fov0":44.0, "clear_r":1.5})

func _stage_meteor(blue: Array, red: Array) -> void:
	# Our Archmage calls the sky down on a squad of theirs; they go up with it.
	var c := SPOT + Vector2(0.0, -9.0)
	var am := _put(blue[0], "mage", true, SPOT, c)
	var squad := []
	for k in 5:
		var e := _put(red[k], ["knight", "barbarian", "knight", "rogue", "barbarian"][k], k == 1,
			c + Vector2(cos(k * 1.26), sin(k * 1.26)) * (0.6 + (k % 2) * 1.0), SPOT)
		_sturdy(e)
		squad.append(e)
	set_meta("squad", squad.map(func(x): return x.id))
	set_meta("meteor_c", c)
	_beat(0.3, func():
		am.face = Sim.angle_of(c - (am.pos as Vector2))
		_attack(am, "ability", false))
	for k in 3:
		_beat(0.2 + k * 0.4, func():
			for e in squad:
				if s.alive(e):
					e.face = Sim.angle_of((am.pos as Vector2) - (e.pos as Vector2)))
	_cam(0.0, 1.0, {"kind":"world", "e0":_g(SPOT + Vector2(1.1, -3.2), 1.5), "l0":_g(SPOT, 1.85),
		"e1":_g(SPOT + Vector2(0.9, -2.8), 1.45), "l1":_g(SPOT, 1.95), "fov0":42.0, "clear_r":1.5})
	_cam(1.0, 3.6, {"kind":"world", "e0":_g(c + Vector2(5.8, -6.2), 2.3), "l0":_g(c, 2.3),
		"e1":_g(c + Vector2(5.4, -5.8), 2.1), "l1":_g(c, 1.8), "fov0":52.0, "clear_r":2.0})

func _stage_volley(blue: Array, red: Array) -> void:
	# Five archers loose together -- the arrows come at us, slowed.
	var archers := []
	for k in 5:
		var a := _put(blue[k], "ranger", k == 2, SPOT + Vector2(-3.2 + k * 1.6, (k % 2) * 0.7), SPOT + Vector2(0.0, -10.0))
		archers.append(a)
	for k2 in 2:
		_beat(0.35 + k2 * 1.1, func():
			for a in archers:
				a.face = Sim.angle_of(Vector2(randf_range(-0.10, 0.10), -1.0))
				_attack(a, "ability", false))
	_cam(0.0, 3.0, {"kind":"world", "e0":_g(SPOT + Vector2(1.8, -8.2), 1.55), "l0":_g(SPOT + Vector2(0.0, 0.0), 1.45),
		"e1":_g(SPOT + Vector2(1.6, -7.6), 1.5), "l1":_g(SPOT, 1.4), "fov0":46.0, "clear_r":1.5})

func _stage_necro(blue: Array, red: Array) -> void:
	var nc := _put(blue[0], "priest", true, SPOT, SPOT + Vector2(-2.6, -3.4))
	var foe := _put(red[0], "knight", true, SPOT + Vector2(-2.6, -3.6), SPOT)
	_sturdy(foe)
	var foe2 := _put(red[1], "barbarian", false, SPOT + Vector2(-4.6, -2.0), SPOT)
	_sturdy(foe2)
	set_meta("necro", nc.id)
	for k in 12:
		_beat(0.15 + k * 0.22, func(): s.act(nc.id, "attack"))
	_beat(0.3, func():
		foe.face = Sim.angle_of((nc.pos as Vector2) - (foe.pos as Vector2))
		_anim(foe.id, "g/Hit_A", 0.6, 3.0))
	var mid := SPOT + Vector2(-1.3, -1.8)
	_cam(0.0, 2.8, {"kind":"world", "e0":_g(mid + Vector2(4.6, -3.6), 1.7), "l0":_g(mid, 1.4),
		"e1":_g(mid + Vector2(4.2, -3.2), 1.6), "l1":_g(mid, 1.45), "fov0":44.0, "clear_r":1.5})

func _stage_sniper(blue: Array, red: Array) -> void:
	# The Sniper's piercing shot down a line of three -- from the side.
	var sn := _put(blue[0], "ranger", true, SPOT, SPOT + Vector2(0.0, -1.0))
	var line := []
	for k in 3:
		var e := _put(red[k], ["knight", "barbarian", "knight"][k], false, SPOT + Vector2(0.12 * k, -5.0 - k * 1.8), SPOT)
		_sturdy(e)
		walkers[e.id] = Vector2(0.0, 1.0) * 0.8
		line.append(e)
	set_meta("line", line.map(func(x): return x.id))
	_beat(0.25, func():
		sn.face = Sim.angle_of(Vector2(0.0, -1.0))
		_attack(sn, "ability", false))
	_cam(0.0, 2.4, {"kind":"world", "e0":_g(SPOT + Vector2(6.8, -2.2), 1.55), "l0":_g(SPOT + Vector2(0.0, -3.4), 1.3),
		"e1":_g(SPOT + Vector2(6.5, -2.6), 1.5), "l1":_g(SPOT + Vector2(0.0, -3.8), 1.3), "fov0":46.0, "clear_r":1.5})

func _stage_rogue(blue: Array, red: Array) -> void:
	# The Assassin leaps on their archer -- against the low sun.
	var rg := _put(blue[0], "rogue", true, SPOT + Vector2(-1.6, 0.4), SPOT + Vector2(2.4, -2.6))
	var arc := _put(red[0], "ranger", false, SPOT + Vector2(-1.6, 0.4) + Vector2(4.0, -3.0).normalized() * 3.0, SPOT + Vector2(6.0, -6.0))
	_sturdy(arc)                                     # (he goes down when the blade lands: the beat below)
	set_meta("rogue_v", arc.id)
	set_meta("rogue_s", rg.id)
	_beat(0.2, func():
		rg.face = Sim.angle_of((arc.pos as Vector2) - (rg.pos as Vector2))
		_attack(rg, "ability", false))
	_beat(0.47, func(): _kill(arc, rg.pos, 7.5, 4.5, rg))        # (as the blade lands, whether or not the lunge connected)
	_cam(0.0, 2.5, {"kind":"world", "e0":_g(SPOT + Vector2(0.9, 5.2), 1.3), "l0":_g(SPOT + Vector2(0.6, -1.0), 1.55),
		"e1":_g(SPOT + Vector2(1.2, 4.8), 1.3), "l1":_g(SPOT + Vector2(0.9, -1.2), 1.5), "fov0":44.0, "clear_r":1.5})

func _stage_shield(blue: Array, red: Array) -> void:
	# A Knight's shield up as their archers loose at him: the arrows glance off.
	var kn := _put(blue[0], "knight", false, SPOT, SPOT + Vector2(0.0, -1.0))
	_sturdy(kn)
	var shooters := []
	for k in 3:
		var e := _put(red[k], "ranger", k == 1, SPOT + Vector2(-2.6 + k * 2.6, -8.5 - (k % 2)), SPOT)
		_sturdy(e)
		shooters.append(e)
	_beat(0.45, func(): s.act(kn.id, "block"))
	for k2 in 2:
		_beat(0.55 + k2 * 0.25, func():
			for e in shooters:
				e.face = Sim.angle_of((kn.pos as Vector2) - (e.pos as Vector2))
				_attack(e, "ability" if k2 == 0 else "attack", false))
	_cam(0.0, 2.4, {"kind":"world", "e0":_g(SPOT + Vector2(2.7, -3.0), 1.2), "l0":_g(SPOT + Vector2(0.0, 0.0), 1.5),
		"e1":_g(SPOT + Vector2(2.4, -2.6), 1.2), "l1":_g(SPOT, 1.5), "fov0":44.0, "clear_r":1.5})

func _red_gate() -> Dictionary:
	return s.gates.filter(func(g): return g.team == 1 and str(g.get("kind", "")) != "jail" and (g.c as Vector2).x > 0.0)[0]

func _stage_gate(blue: Array, red: Array) -> void:
	# Their gate from inside their courtyard: our bomb comes over, lands at the doors -- and they blow in on their guards.
	var gate := _red_gate()
	var gc: Vector2 = gate.c                                  # (7, -44)
	var gfront: Vector2 = Sim.gate_front(gate)                # outside it (towards midfield)
	gate.hp = float(gate.max_hp) * 0.45
	var thrower := _put(blue[0], "barbarian", false, gfront + Vector2(0.4, 9.2), gfront)
	_sturdy(thrower)
	s.bombs[0] = {"id":0, "team":0, "state":"carried", "p":thrower.pos, "h":1.9, "carrier":thrower.id, "by":"",
		"from":Vector2.ZERO, "to":Vector2.ZERO, "t0":0.0, "lit_at":-1.0}
	thrower["bomb_held"] = true
	var guards := []
	for k in 5:
		var gp: Vector2 = gc + Vector2([-4.2, -2.7, 2.7, 4.2, -1.3][k], [-4.6, -5.4, -5.4, -4.6, -7.2][k])     # (> GATE_OPEN_RADIUS)
		var e := _put(red[k], ["knight", "barbarian", "knight", "rogue", "knight"][k], k == 2, gp, gc)
		_sturdy(e)
		guards.append(e)
	set_meta("guards", guards.map(func(x): return x.id))
	set_meta("gate_i", s.gates.find(gate))
	_beat(1.75, func():                            # (late enough that the shortened fuse's lit_at stays >= 0: lit)
		thrower.face = Sim.angle_of(gfront - (thrower.pos as Vector2))
		s.act(thrower.id, "interact")
		var b: Dictionary = s.bombs[0]
		b.lit_at = s.time + 0.80 - Sim.BOMB_FUSE)
	# inside their courtyard, low, looking out at the doors (they blow in towards us)
	_cam(0.0, 4.6, {"kind":"world", "e0":_g(gc + Vector2(0.9, -12.0), 1.7), "l0":_g(gc + Vector2(0.0, 0.0), 2.2),
		"e1":_g(gc + Vector2(0.8, -11.2), 1.6), "l1":_g(gc, 2.4), "fov0":46.0, "shake_from":2.55, "shake":0.0})

# --- the heist: their cell smashed open in slow motion; our King lifted high; out they run ---
func _stage_heist(blue: Array, red: Array) -> void:
	var cell: Vector2 = Sim.cell(0)
	var jail: Dictionary = s.gates.filter(func(g): return g.team == 1 and str(g.get("kind", "")) == "jail")[0]
	var out: Vector2 = ((jail.c as Vector2) - cell).normalized()
	var side := Vector2(out.y, -out.x)
	var fy := Sim.height_at(cell)
	jail.hp = 30.0
	var smasher := _put(blue[0], "barbarian", true, (jail.c as Vector2) + out * 1.3, cell)
	_sturdy(smasher)
	var crew := []
	for k in 3:
		var p: Vector2 = (jail.c as Vector2) + out * (4.6 + k * 0.6) + side * (-1.5 + k * 1.5)
		var a := _put(blue[1 + k], ["knight", "knight", "barbarian"][k], k == 0, p, cell)
		_sturdy(a)
		crew.append(a)
	set_meta("crew", crew.map(func(x): return x.id))
	_beat(0.35, func(): _attack(smasher, "attack", false))
	_beat(0.62, func():                             # the blow that breaks it (as the swing lands)
		jail.hp = 1.0
		_attack(smasher, "attack", false))
	_beat(1.08, func():                             # (in case the swing missed the door: it breaks all the same)
		if not bool(jail.broken):
			printerr("JAIL forced")
			jail.hp = 0.0
			jail.broken = true
			s._update_gate_nav()
			s._event("gate_broken", {"gate":s.gates.find(jail), "team":1, "by":smasher.id}))
	_beat(1.8, func():                              # the crew rush in past him
		walkers.erase(smasher.id)
		smasher.pos = (jail.c as Vector2) + out * 1.6 + side * 2.2
		for a in crew:
			routes[a.id] = [cell + out * 0.6 + side * ((crew.find(a) - 1) * 0.5)])
	_beat(3.4, func():
		var o: Dictionary = s.oracles[0]
		for a in crew:
			routes.erase(a.id)
			a.move = Vector2.ZERO
			s._join_lift(a, o))
	_beat(4.4, func():
		var lead: Dictionary = s.by_id[(s.oracles[0].lifters as Array)[0]]
		walkers[lead.id] = out * 1.0)
	# Inside the cell over the King's shoulder: the door smashed in (slow motion); outside the door as he's lifted
	# high; ahead of them in the corridor as they carry him out.
	_cam(0.0, 2.4, {"kind":"world", "e0":_v(cell - out * 1.35 + side * 1.25, fy + 2.9), "l0":_v((jail.c as Vector2) + out * 1.0, fy + 1.5),
		"e1":_v(cell - out * 1.3 + side * 1.2, fy + 2.85), "l1":_v((jail.c as Vector2) + out * 1.0, fy + 1.55), "fov0":50.0, "clear_r":-1.0})
	_cam(2.4, 4.4, {"kind":"world", "e0":_v((jail.c as Vector2) + out * 4.4 + side * 0.7, fy + 1.3), "l0":_v(cell + out * 0.2, fy + 2.4),
		"e1":_v((jail.c as Vector2) + out * 4.1 + side * 0.6, fy + 1.2), "l1":_v(cell + out * 0.2, fy + 3.1), "fov0":50.0, "clear_r":-1.0})
	_cam(4.4, 8.0, {"kind":"world", "e0":_v((jail.c as Vector2) + out * 6.6 + side * 0.7, fy + 1.5), "l0":_v(cell + out * 1.5, fy + 2.7),
		"e1":_v((jail.c as Vector2) + out * 7.4 + side * 0.8, fy + 1.6), "l1":_v((jail.c as Vector2) + out * 2.5, fy + 2.7), "fov0":48.0, "clear_r":-1.0})

# --- the run home: carrying our King over the bridge into the sunset; an ambush; our gates ---
func _carry_group(at: Vector2, dir: Vector2, crew: Array) -> void:
	# The crew (already lifting) put down at `at`, heading `dir` (followers are placed round the lead by the sim).
	var o: Dictionary = s.oracles[0]
	var lead: Dictionary = s.by_id[(o.lifters as Array)[0]]
	lead.pos = at
	lead.face = Sim.angle_of(dir)
	o.pos = at
	for id in o.lifters:
		var f: Dictionary = s.by_id[id]
		f.pos = at
		f.face = Sim.angle_of(dir)
	walkers[lead.id] = dir

func _stage_carry(blue: Array, red: Array) -> void:
	var o: Dictionary = s.oracles[0]
	var crew := []
	for k in 3:
		var a := _put(blue[k], ["knight", "barbarian", "knight"][k], k == 0, Sim.cell(0) + Vector2(0.4 * k, 0.6), Sim.cell(0))
		_sturdy(a)
		crew.append(a)
	o.state = "cell"
	for a in crew:
		s._join_lift(a, o)
	var escorts := []
	for k in 4:
		var e := _put(blue[3 + k], ["knight", "ranger", "barbarian", "knight"][k], k % 2 == 0, park[0], park[0])
		_sturdy(e)
		escorts.append(e)
	# 1) over the east crossing, running south into camera, the low sun behind them; their pursuers behind.
	var b0 := Vector2(24.2, -9.5)                       # (the east crossing: (24, -7) to (24, 5))
	var bdir := Vector2(0.0, 1.0)
	_beat(0.0, func():
		_carry_group(b0, bdir, crew)
		for k in escorts.size():
			var e: Dictionary = escorts[k]
			e.pos = b0 + Vector2([-1.9, 1.9, -1.5, 1.6][k], [-1.6, -2.0, 1.6, 1.3][k])
			e.face = Sim.angle_of(bdir)
			walkers[e.id] = bdir * 0.92)
	var chasers := []
	for k in 3:
		var e := _put(red[k], ["rogue", "barbarian", "knight"][k], false, b0 + Vector2(-1.0 + k, -7.0 - k), b0)
		_sturdy(e)
		walkers[e.id] = bdir
		chasers.append(e)
	_cam(0.0, 3.8, {"kind":"follow", "id":crew[0].id, "e0":Vector3(0.9, 1.2, 6.4), "l0":Vector3(0.0, 2.7, -1.0),
		"e1":Vector3(0.7, 1.1, 5.6), "l1":Vector3(0.0, 2.8, -1.0), "fov0":40.0, "shake":0.04})
	# 2) up the path: their Berserker charges at them head on -- our Crusader, out in front, hurls the hammer and it
	#    takes him off his feet (slow motion). From the side of the path, panning with them.
	var a0 := Vector2(20.0, 13.0)                       # (on the path up from the east crossing)
	var adir := Vector2(-0.12, 1.0).normalized()
	var aleft := adir.rotated(PI * 0.5)                  # (towards the camera's side: west)
	var amb: Dictionary = red[3]
	_put(amb, "barbarian", true, park[1], park[1])
	_sturdy(amb)
	var cru: Dictionary = escorts[0]
	_beat(3.8, func():
		for e in chasers:
			walkers.erase(e.id)
			e.pos = park[1]
		_carry_group(a0, adir, crew)
		for k in escorts.size():
			var e: Dictionary = escorts[k]
			e.pos = a0 - aleft * [1.8, 1.6, 1.2, 1.4][k] * (1.0 if k % 2 == 0 else -1.0) + adir * [1.4, 0.4, -1.6, -1.0][k]
			e.face = Sim.angle_of(adir)
			walkers[e.id] = adir * 0.92
		cru.pos = a0 + adir * 2.4 - aleft * 0.9
		amb.pos = a0 + adir * 13.0 + aleft * 0.6
		amb.face = Sim.angle_of(a0 - (amb.pos as Vector2))
		walkers[amb.id] = (a0 - (amb.pos as Vector2)).normalized())
	_beat(4.95, func():
		walkers.erase(cru.id)
		cru.move = Vector2.ZERO
		cru.face = Sim.angle_of((amb.pos as Vector2) - (cru.pos as Vector2))
		s._throw_hammer(cru))
	set_meta("ambusher", amb.id)
	set_meta("striker", cru.id)
	var eye2: Vector2 = a0 + adir * 5.0 + aleft * 9.5
	_cam(3.8, 8.4, {"kind":"track", "eye":_g(eye2, 1.9), "id":crew[0].id, "l":Vector3(0.0, 2.0, 0.0), "lead":_v(adir * 1.6, 0.0), "fov0":40.0, "clear_r":1.5})
	# 3) home: they come up to our east gate, its doors swinging open for them; over them from behind.
	var g0 := Vector2(7.0, 31.0)
	_beat(8.4, func():
		walkers.erase(amb.id)
		_carry_group(g0, Vector2(0.0, 1.0), crew)
		for k in escorts.size():
			var e: Dictionary = escorts[k]
			e.pos = g0 + Vector2([-1.7, 1.7, -1.2, 1.3][k], [1.1, 0.7, -1.6, -1.4][k])
			e.face = 0.0
			walkers[e.id] = Vector2(0.0, 1.0) * 0.92)
	_cam(8.4, 12.5, {"kind":"world", "e0":Vector3(3.0, 5.8, 24.5), "l0":Vector3(7.0, 1.8, 40.0),
		"e1":Vector3(3.8, 5.2, 27.5), "l1":Vector3(7.0, 2.0, 42.5), "fov0":46.0})

# --- the throne: up the last steps in slow motion; he's set down on his throne; the rescue ---
func _stage_throne(blue: Array, red: Array) -> void:
	park[0] = Sim._c(0, Vector2(-19.0, 6.0))
	for u in blue:
		u.pos = park[0]
	var o: Dictionary = s.oracles[0]
	var crew := []
	for k in 3:
		var a := _put(blue[k], ["knight", "barbarian", "knight"][k], k == 0, Sim.cell(0), Sim.cell(0))
		_sturdy(a)
		crew.append(a)
	for a in crew:
		s._join_lift(a, o)
	var th: Vector2 = Sim.throne(0)                     # (0, 67.8)
	var start := th + Vector2(0.0, -8.0)
	_carry_group(start, Vector2(0.0, 1.0), crew)
	# allies round the throne room, turning to watch
	for k in 6:
		var p: Vector2 = th + Vector2([-4.5, -3.6, 3.8, 4.6, -5.4, 5.5][k], [-1.0, -3.4, -3.2, -0.8, -5.0, -5.2][k])
		_put(blue[3 + k], ["knight", "ranger", "barbarian", "mage", "priest", "knight"][k], k % 2 == 1, p, start)
	_beat(1.15, func():
		for k in 6:
			var u: Dictionary = blue[3 + k]
			u.face = Sim.angle_of(th - (u.pos as Vector2)))
	set_meta("throne_crew", crew.map(func(x): return x.id))
	var thy := Sim.height_at(th)
	_cam(0.0, 3.6, {"kind":"world", "e0":_v(th + Vector2(1.6, 1.0), thy + 0.9), "l0":_v(th + Vector2(0.0, -4.0), thy + 2.4),
		"e1":_v(th + Vector2(1.3, 0.8), thy + 0.8), "l1":_v(th + Vector2(0.0, -2.0), thy + 2.8), "fov0":48.0})

# --- the plate behind the title: the whole battle far below at golden hour, a slow drift ---
func _stage_titlebg(blue: Array, red: Array) -> void:
	for k in blue.size():
		_put(blue[k], ["knight", "barbarian", "ranger", "mage", "rogue", "priest", "knight"][k % 7], k % 3 == 0,
			Vector2(-12.0 + (k % 8) * 3.2, 9.0 + (k / 8) * 2.5), Vector2(0.0, 0.0), true)
	for k in red.size():
		_put(red[k], ["knight", "barbarian", "ranger", "mage", "rogue", "priest", "knight"][k % 7], k % 3 == 1,
			Vector2(-12.0 + (k % 8) * 3.2, -9.0 - (k / 8) * 2.5), Vector2(0.0, 0.0), true)
	_cam(0.0, 14.0, {"kind":"world", "e0":Vector3(26.0, 26.0, 40.0), "l0":Vector3(0.0, 0.0, -6.0),
		"e1":Vector3(18.0, 23.0, 36.0), "l1":Vector3(-2.0, 0.0, -8.0), "fov0":46.0, "lin":true})

# ---------- per frame ----------
func _slow(tt: float) -> float:
	var keys: Array = SCALE.get("charge" if run.begins_with("charge") else run, [])
	if run.begins_with("charge"):
		if not has_meta("clash_at"):
			return 1.0
		tt -= float(get_meta("clash_at"))
	if keys.is_empty() or tt < float(keys[0][0]):
		return 1.0
	for i in keys.size() - 1:
		if tt >= float(keys[i][0]) and tt < float(keys[i + 1][0]):
			var k := (tt - float(keys[i][0])) / maxf(0.0001, float(keys[i + 1][0]) - float(keys[i][0]))
			return lerpf(float(keys[i][1]), float(keys[i + 1][1]), k)
	return float(keys[keys.size() - 1][1])

func _shake(amount: float) -> Vector3:
	return Vector3(sin(t * 7.3) + 0.5 * sin(t * 17.9 + 1.3), 0.6 * sin(t * 9.1 + 0.7) + 0.3 * sin(t * 23.0), cos(t * 6.1 + 2.1)) * amount

var vtime := 0.0              # recording seconds (frames / 30): camera moves run on these, so they glide through slow motion

func _apply_cam() -> void:
	var seg: Array = []
	for c in cams:
		if t >= float(c[0]) and t < float(c[1]):
			seg = c
	if seg.is_empty():
		seg = cams[cams.size() - 1]
	var spec: Dictionary = seg[2]
	if cams.find(seg) != cam_seg:
		cam_seg = cams.find(seg)
		set_meta("seg_v0", vtime)
		printerr("CAMSEG %d %s frame %d t=%.3f v=%.3f" % [cam_seg, spec.kind, frames, t, vtime])
	var u := clampf((t - float(seg[0])) / maxf(0.001, float(seg[1]) - float(seg[0])), 0.0, 1.0)
	if not bool(spec.get("lin", false)):
		u = _ease(u)
	var eye := Vector3.ZERO
	var look := Vector3.ZERO
	var fov := lerpf(float(spec.get("fov0", 52.0)), float(spec.get("fov1", spec.get("fov0", 52.0))), u)
	match str(spec.kind):
		"world":
			eye = (spec.e0 as Vector3).lerp(spec.e1, u)
			look = (spec.l0 as Vector3).lerp(spec.l1, u)
		"follow":
			var a := _actor(str(spec.id))
			var base: Vector3 = (a.root as Node3D).position if not a.is_empty() else _g(s.by_id[spec.id].pos)
			eye = base + (spec.e0 as Vector3).lerp(spec.e1, u)
			look = base + (spec.l0 as Vector3).lerp(spec.l1, u)
		"group":
			var sum := Vector3.ZERO
			var n := 0
			for id in spec.ids:
				var a2 := _actor(str(id))
				if not a2.is_empty() and s.alive(s.by_id[id]):
					sum += (a2.root as Node3D).position
					n += 1
			if n > 0:
				set_meta("grp_" + str(cam_seg), sum / float(n))
			var base2: Vector3 = get_meta("grp_" + str(cam_seg), Vector3.ZERO)
			eye = base2 + (spec.e0 as Vector3).lerp(spec.e1, u)
			look = base2 + (spec.l0 as Vector3).lerp(spec.l1, u)
		"track":
			var at := _actor(str(spec.id))
			var tp: Vector3 = (at.root as Node3D).position if not at.is_empty() else _g(s.by_id[spec.id].pos)
			eye = spec.eye
			look = tp + (spec.l as Vector3) + (spec.get("lead", Vector3.ZERO) as Vector3)
		"orbit":
			var ang := lerpf(float(spec.a0), float(spec.a1), u)
			var c: Vector3 = spec.c
			eye = c + Vector3(cos(ang) * float(spec.r), float(spec.h), sin(ang) * float(spec.r))
			look = c + Vector3(0.0, 0.3, 0.0)
	var sh := float(spec.get("shake", 0.0))
	if spec.has("shake_from") and t >= float(spec.shake_from):
		sh = 0.22 * exp(-(t - float(spec.shake_from)) * 3.0)
	if sh > 0.0:
		eye += _shake(sh)
		look += _shake(sh * 0.6)
	mode.view.cam_override = [eye, look]
	mode.view.camera.fov = fov
	if not props.is_empty() and float(spec.get("clear_r", 1.1)) >= 0.0:
		_clear_view(eye, look, float(spec.get("clear_r", 1.1)))

func _smooth_bomb(delta: float) -> void:
	# (as trailer 6) the bomb in flight placed on the sim's own curve at this frame's exact time: no steps in slow motion
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

func _process(delta: float) -> bool:
	frames += 1
	mode._guard_clock = -1.0e9
	if frames == 2:
		_stage()
	if frames < 2:
		return false
	_quiet()
	t += delta
	vtime = float(frames - 3) / 30.0
	frame_dt = delta
	if still_at >= 0.0 and frames == 3:
		t = still_at
	Engine.time_scale = _slow(t)
	_smooth_bomb(delta)
	for b in beats.duplicate():
		if t >= float(b[0]):
			beats.erase(b)
			(b[1] as Callable).call()
	_apply_cam()
	for id in routes.keys():
		var ru: Dictionary = s.by_id[id]
		if not s.alive(ru):
			continue
		var pts: Array = routes[id]
		while pts.size() > 1 and (ru.pos as Vector2).distance_to(pts[0]) < 0.9:
			pts.remove_at(0)
		var to: Vector2 = (pts[0] as Vector2) - (ru.pos as Vector2)
		if pts.size() == 1 and to.length() < 0.5:
			routes.erase(id)
			ru.move = Vector2.ZERO
			continue
		ru.move = to.normalized()
	for id in walkers:
		var wu: Dictionary = s.by_id[id]
		if s.alive(wu):
			wu.move = walkers[id]
	_run_specials()
	_keep_sturdy()
	if not torches.is_empty():
		_flicker()
	if OS.has_environment("DEBUG") and frames % 10 == 0:
		_debug()
	if still_at >= 0.0 and frames == 7:
		root.get_texture().get_image().save_png("%s/still_%s_%.2f.png" % [out_dir, run, still_at])
		printerr("SHOT_DONE %s still" % run)
		quit(0)
		return false
	if t >= float(LENGTH[run]) or (until > 0.0 and t >= until):
		printerr("SHOT_DONE %s %d frames" % [run, frames])
		quit(0)
	return false

func _debug() -> void:
	match run:
		"charge", "charge2", "charge3":
			var fb: Array = get_meta("front_b")
			var fr: Array = get_meta("front_r")
			var gap := INF
			for a in fb:
				for b in fr:
					gap = minf(gap, (s.by_id[a].pos as Vector2).distance_to(s.by_id[b].pos))
			var zb := 0.0
			for a in fb:
				zb += (s.by_id[a].pos as Vector2).y / fb.size()
			var zr := 0.0
			for b in fr:
				zr += (s.by_id[b].pos as Vector2).y / fr.size()
			var rg := ""
			for ra in mode.view._ragdolls:
				var sim3 = ra.rag.sim
				var pbs: Array = (sim3 as Node).get_children().filter(func(n): return n is PhysicalBone3D)
				if not pbs.is_empty():
					var hp3: Vector3 = (pbs[0] as Node3D).global_position
					rg += " (%.1f,%.1f,%.1f v%.1f)" % [hp3.x, hp3.y, hp3.z, (pbs[0] as PhysicalBone3D).linear_velocity.length()]
			printerr("t=%.2f gap %.2f front z blue %.1f red %.1f rags %d%s" % [t, gap, zb, zr, mode.view._ragdolls.size(), rg])
		"gate":
			var bb: Dictionary = s.bombs[0]
			var gg: Dictionary = _red_gate()
			printerr("t=%.2f st=%.2f lit_at %.2f bomb %s gate open %s hp %.0f broken %s" % [t, s.time, float(bb.get("lit_at", -9.0)), str(bb.get("state", "-")) + " " + str(bb.get("p", "")),
				str(gg.open), float(gg.hp), str(gg.broken)])
		"rogue":
			var v: Dictionary = s.by_id[get_meta("rogue_v")]
			var r2: Dictionary = s.by_id[get_meta("rogue_s")]
			printerr("t=%.2f victim %s %s hp %.0f  rogue %s %s" % [t, str(v.state), str(v.pos), float(v.hp), str(r2.state), str(r2.pos)])
		"heist", "carry", "throne":
			var o: Dictionary = s.oracles[0]
			var jl: Dictionary = s.gates.filter(func(g): return g.team == 1 and str(g.get("kind", "")) == "jail")[0]
			var lead: Dictionary = s.by_id.get(str(o.carrier), {})
			printerr("t=%.2f king %s %s lifters %d lead %s jail broken %s hp %.0f" % [t, str(o.state), str(o.pos), (o.lifters as Array).size(),
				str(lead.get("pos", "-")) + " " + str(lead.get("state", "")), str(jl.broken), float(jl.hp)])
		_:
			printerr("t=%.2f" % t)

func _clash_step() -> void:
	# The front ranks within CLASH_GAP: every front man swings, time all but stops; as the blows land (CLASH_HIT
	# later) their front rank is thrown back off its feet, two of ours too.
	var fb: Array = get_meta("front_b")
	var fr: Array = get_meta("front_r")
	if not has_meta("clash_at"):
		var gap := INF
		for a in fb:
			for b in fr:
				gap = minf(gap, (s.by_id[a].pos as Vector2).distance_to(s.by_id[b].pos))
		if gap < CLASH_GAP:
			set_meta("clash_at", t)
			printerr("CLASH t=%.3f v=%.3f gap %.2f" % [t, vtime, gap])
			for id in fb + fr:
				walkers.erase(id)
				_attack(s.by_id[id])
	if has_meta("clash_at") and not has_meta("resumed") and t >= float(get_meta("clash_at")) + FREEZE_END:
		set_meta("resumed", true)
		printerr("RESUME t=%.3f v=%.3f" % [t, vtime])
	if has_meta("clash_at") and not has_meta("clash_hit") and t >= float(get_meta("clash_at")) + CLASH_HIT:
		set_meta("clash_hit", true)
		printerr("IMPACT t=%.3f v=%.3f" % [t, vtime])
		for k in fr.size():
			var u: Dictionary = s.by_id[fr[k]]
			if k in [1, 2, 4, 5, 6]:
				_kill(u, (u.pos as Vector2) + Vector2(randf_range(-0.6, 0.6), 1.5), 11.0 + randf() * 3.0, 8.0 + randf() * 2.5, s.by_id[fb[k]])
		for k in [3, 7]:
			var u2: Dictionary = s.by_id[fb[k]]
			_kill(u2, (u2.pos as Vector2) + Vector2(randf_range(-0.5, 0.5), -1.5), 7.5 + randf() * 2.0, 5.0 + randf() * 2.0, s.by_id[fr[k]])

func _run_specials() -> void:
	if run.begins_with("charge"):
		_clash_step()
	# Hammer and whirl: each one hit is thrown, dead.
	if has_meta("rush") and has_meta("striker"):
		var st: Dictionary = s.by_id[get_meta("striker")]
		for rid in get_meta("rush"):
			var ru: Dictionary = s.by_id[rid]
			var hk := "rhp_" + str(rid)
			var was := float(get_meta(hk, ru.hp))
			set_meta(hk, ru.hp)
			if s.alive(ru) and ru.hp < was - 1.0 and float(ru.max_hp) >= 50000.0:
				_kill(ru, st.pos, 8.0 + randf() * 2.0, 5.5 + randf() * 1.5, st)
	# The carry's ambush: the hammer takes him.
	if has_meta("ambusher") and has_meta("striker"):
		var am: Dictionary = s.by_id[get_meta("ambusher")]
		var was2 := float(get_meta("amb_hp", am.hp))
		set_meta("amb_hp", am.hp)
		if s.alive(am) and am.hp < was2 - 1.0:
			_kill(am, s.by_id[get_meta("striker")].pos, 9.0, 6.0, s.by_id[get_meta("striker")])
	# The Sniper's line, the Rogue's victim: dead when hit.
	for key in ["line"]:
		if has_meta(key):
			for id in get_meta(key):
				var lu: Dictionary = s.by_id[id]
				var hk2 := "lhp_" + str(id)
				var was3 := float(get_meta(hk2, lu.hp))
				set_meta(hk2, lu.hp)
				if s.alive(lu) and lu.hp < was3 - 1.0:
					_kill(lu, (lu.pos as Vector2) + Vector2(0.0, 1.0), 6.5, 3.5)
	if has_meta("victim"):
		var vu: Dictionary = s.by_id[get_meta("victim")]
		var was4 := float(get_meta("vhp", vu.hp))
		set_meta("vhp", vu.hp)
		if s.alive(vu) and vu.hp < was4 - 1.0:
			_kill(vu, s.by_id[get_meta("striker")].pos, 7.5, 4.5, s.by_id[get_meta("striker")])
	# The meteor: the squad goes up with it.
	if has_meta("meteor_c") and not has_meta("meteor_done"):
		for m in s.meteors:
			if float(m.burn_until) >= 0.0:
				set_meta("meteor_done", true)
				printerr("IMPACT t=%.3f v=%.3f" % [t, vtime])
				for id in get_meta("squad"):
					_kill(s.by_id[id], m.at, 9.0 + randf() * 3.0, 8.0 + randf() * 3.0)
	# Their gate: the guards blown in with the doors.
	if has_meta("guards") and not has_meta("blown"):
		var b: Dictionary = s.bombs[0]
		if not b.is_empty() and str(b.state) == "lit" and float(b.lit_at) >= 0.0 and s.time + 0.04 >= float(b.lit_at) + Sim.BOMB_FUSE:
			set_meta("blown", true)
			printerr("BOOM t=%.3f v=%.3f" % [t, vtime])
			for gid in get_meta("guards"):
				var gu: Dictionary = s.by_id[gid]
				_kill(gu, b.p, 10.0 + randf() * 3.0, 7.0 + randf() * 3.0)
	# The throne: the lead lets him down on it (no sim rescue: that would send him straight back to their cell).
	if run == "throne" and not has_meta("seated"):
		var o: Dictionary = s.oracles[0]
		if str(o.state) == "carried" and (o.pos as Vector2).distance_to(Sim.throne(0)) < 3.0:      # (the sim's rescue is at 2.2)
			set_meta("seated", true)
			printerr("SEATED t=%.3f v=%.3f" % [t, vtime])
			for id in (o.lifters as Array).duplicate():
				walkers.erase(id)
				s.by_id[id].move = Vector2.ZERO
			var lead: Dictionary = s.by_id[(o.lifters as Array)[0]]
			for id in (o.lifters as Array).duplicate():
				s._leave_lift(s.by_id[id], false)
			o.pos = Sim.throne(0) + Vector2(0.0, 0.5)
			s._event("rescue", {"team":0, "id":lead.id, "n":3})
