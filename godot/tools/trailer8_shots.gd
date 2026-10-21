extends SceneTree
# Fatebound trailer 8, the 5v5 (Kevin: "I want a trailer now. Very cinematic and showing gameplay. Also voice it. I want it
# to feature the dragon roaring for climax along with music ramping up to climax then showing the title animating in").
#
# Short staged runs in a real offline 5v5 on the Rift (siege_mode.gd against bots; never the live server), each recorded
# by Movie Maker, one run a process (tools/trailer8_render.sh <run> [W H]), then cut, mixed and finished by
# tools/trailer8_edit.py. The plan is in tools/trailer8_script.md.
#   RUN=<run>  [SNAP=t1,t2,...: PNG stills at those run times to OUT_DIR, then quit -- for framing, no Movie Maker]
#   [UNTIL=<t>: stop early]  [NOHQ=1: without high-quality graphics]
# Times are game seconds from the staging; SCALE keys ramp the game's speed (slow motion). Camera moves run on game
# time too, so they slow with it. REC_START <frame> marks the staging's frame in the recording (the edit trims to it).
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")

const RUNS := ["map", "vista", "kingred", "charge", "clash", "storm", "meteor", "dive", "slide", "inferno", "rain", "legion", "duel", "tower",
	"kingfight", "breach", "pit", "rise", "roar", "roar2", "title"]
const LENGTH := {"map": 0.4, "vista": 5.6, "kingred": 6.0, "charge": 4.4, "clash": 4.2, "storm": 4.0, "meteor": 4.2, "dive": 3.6,
	"slide": 3.4, "inferno": 3.0, "rain": 4.0, "legion": 4.0, "duel": 3.2, "tower": 4.6, "kingfight": 5.4, "breach": 5.2, "pit": 5.0, "rise": 2.6, "roar": 5.6, "roar2": 5.6,
	"title": 9.8}
# slow motion: [game time, time scale] keys, linear between them (1.0 before the first)
const SCALE := {
	"charge": [[0.0, 0.42]],
	"clash": [[1.05, 1.0], [1.2, 0.3], [2.6, 0.3], [2.9, 0.8]],
	"storm": [[0.6, 1.0], [0.8, 0.55]],
	"meteor": [[0.85, 1.0], [1.0, 0.35], [2.6, 0.35], [2.8, 0.7]],
	"dive": [[0.35, 1.0], [0.5, 0.35], [1.6, 0.35], [1.8, 0.8]],
	"slide": [[0.35, 1.0], [0.5, 0.35]],
	"inferno": [[0.3, 1.0], [0.42, 0.25], [1.4, 0.25], [1.7, 0.7]],
	"rain": [[0.5, 1.0], [0.7, 0.5]],
	"legion": [[0.3, 1.0], [0.45, 0.5]],
	"duel": [[0.45, 1.0], [0.6, 0.22], [2.2, 0.22], [2.5, 0.6]],
	"tower": [[1.5, 1.0], [1.6, 0.3], [3.4, 0.3]],
	"kingfight": [[0.0, 0.6]],
	"breach": [[0.8, 1.0], [0.95, 0.32], [1.7, 0.32], [2.1, 0.75]],
	"rise": [[0.0, 0.2]],
	"roar": [[2.2, 1.0], [2.35, 0.28]],
	"roar2": [[2.2, 1.0], [2.35, 0.28]],
}
# the sides: you and b1..b4, r0..r4 (the icon's Knight and Barbarian lead them)
const BLUE := {"you": "knight", "b1": "stormcaller", "b2": "dragoon", "b3": "archmage", "b4": "golem"}
const RED := {"r0": "barbarian", "r1": "necromancer", "r2": "musketeer", "r3": "assassin", "r4": "berserker"}
const PARK := [Vector2(-50.0, 62.0), Vector2(50.0, -62.0)]      # (out of every shot, under their own towers)
const PIT := Vector2(26.0, 3.877)                              # the Grave Wyrm's island (moba.WYRM_P)

var mode
var s
var sm
var run := "vista"
var frames := 0
var staged := false
var rec0 := 0
var t := 0.0
var cams: Array = []            # [t0, t1, {kind, ...}]
var beats: Array = []           # [t, Callable]
var walkers := {}               # id -> move (a fraction of the unit's speed)
var sturdy := {}
var snaps: Array = []
var until := -1.0
var cam_seg := -1
var out_dir := "/tmp/trailer8"
var glow_light: OmniLight3D = null

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")
	run = OS.get_environment("RUN") if OS.has_environment("RUN") else run
	if OS.has_environment("SNAP"):
		for v in OS.get_environment("SNAP").split(","):
			snaps.append(float(v))
	if OS.has_environment("UNTIL"):
		until = float(OS.get_environment("UNTIL"))
	if OS.has_environment("OUT_DIR"):
		out_dir = OS.get_environment("OUT_DIR")
	seed(8)
	mode = Mode.new()
	mode.moba_hero = "knight"
	mode.match_seed = 2026
	mode.hq_gfx = OS.get_environment("NOHQ") != "1"
	root.add_child(mode)

# ---------- helpers ----------
func _g(p: Vector2, up := 0.0) -> Vector3:
	return Vector3(p.x, Sim.height_at(p) + up, p.y)

func _u(id: String) -> Dictionary:
	return s.by_id[id]

func _actor(id: String) -> Dictionary:
	return mode.view.actors.get(id, {})

func _level(u: Dictionary, lv: int) -> void:
	lv = mini(lv, int(sm.LEVEL_MAX))
	while int(u.level) < lv:
		sm.add_xp(u, sm.need(int(u.level)))
	u.picks = []

func _place(id: String, p: Vector2, face_to: Vector2) -> Dictionary:
	var u := _u(id)
	u.pos = p
	u.move = Vector2.ZERO
	u.task = {}
	u.face = Sim.angle_of((face_to - p).normalized()) if face_to != p else u.face
	return u

func _face(id: String, to: Vector2) -> void:
	var u := _u(id)
	u.face = Sim.angle_of((to - (u.pos as Vector2)).normalized())

func _sturdy(id: String) -> void:
	sturdy[id] = true

func _keep_sturdy() -> void:
	for id in sturdy:
		var u := _u(id)
		if s.alive(u) and float(u.hp) < float(u.max_hp) * 0.5:
			u.hp = float(u.max_hp)

func _cast(id: String, what: String) -> void:
	var u := _u(id)
	match what:
		"r":
			u.ult_cd = 0.0
			s.act(id, "ult")
		"q":
			u.cd_ability = 0.0
			s.act(id, "ability")
		"a":
			u.cd_attack = 0.0
			s.act(id, "attack")
		_:
			u["cd_" + what] = 0.0
			s.act(id, "spell", what)

func _stop_all(ids: Array) -> void:
	walkers.clear()
	mode.hud._stick_active = false
	for id in ids:
		_u(str(id)).move = Vector2.ZERO

func _face_cast(id: String, other: String, what: String) -> void:
	_face(id, _u(other).pos)
	_cast(id, what)

func _hit(id: String, at_p: Vector2) -> void:
	_face(id, at_p)
	_cast(id, "a")

func _kill(id: String, from: Vector2, speed: float, up: float, by := "") -> void:
	var u := _u(id)
	if not s.alive(u):
		return
	s._next_push = s._push_from(from, u.pos, speed, up)
	s._kill(s.by_id.get(by, {}), u)
	u.respawn_at = INF
	walkers.erase(id)
	sturdy.erase(id)

func _walk(id: String, dir: Vector2, speed: float) -> void:
	# a steady run at speed m/s whatever the hero's own (so a line keeps its shape)
	var u := _u(id)
	walkers[id] = dir.normalized() * minf(1.0, speed / maxf(0.1, float(s.stat(u, "speed"))))

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
	mode.hud._toast = ""

func _hide_rings() -> void:
	# (the team rings under everyone: a game's marks, not a film's; the view shows them again each frame, so their mesh
	# goes instead)
	for a in mode.view.actors.values():
		if a.get("ring") != null and is_instance_valid(a.ring):
			(a.ring as MeshInstance3D).mesh = null
	for mt in mode.view.moba_towers.values():          # (and the towers' range rings)
		if (mt as Dictionary).get("ring") != null and is_instance_valid(mt.ring):
			(mt.ring as MeshInstance3D).mesh = null

func _reveal_all() -> void:
	# no fog of war in the film: every unit seen by both sides (the view hides what your side can't see)
	for u in s.units:
		u["rev_until"] = s.time + 5.0

func _drive_you() -> void:
	# the player's hero moves by the stick (siege_mode sets his move from it every frame): walked, the stick is pushed
	var hud = mode.hud
	if walkers.has("you") and s.alive(_u("you")):
		hud._stick_active = true
		hud._stick_origin = Vector2.ZERO
		hud._stick_pos = (walkers["you"] as Vector2) * 60.0
	else:
		hud._stick_active = false

# ---------- light ----------
func _env() -> Environment:
	for w in mode.view.find_children("*", "WorldEnvironment", true, false):
		return (w as WorldEnvironment).environment
	return null

func _sun() -> DirectionalLight3D:
	for l in mode.view.find_children("*", "DirectionalLight3D", true, false):
		return l
	return null

func _golden() -> void:
	# late afternoon, the sun low beyond their castle: long shadows, warm light (as trailers 4, 6 and 7)
	var d := Vector3(0.35, 0.30, -1.0).normalized()
	var sun := _sun()
	sun.global_transform.basis = Basis.looking_at(-d)
	sun.light_color = Color("#ffd2a0")
	sun.light_energy = 1.25
	var env := _env()
	var sky := env.sky.sky_material as ProceduralSkyMaterial if env.sky != null else null
	if sky != null:
		sky.sky_top_color = Color("#3d5f93")
		sky.sky_horizon_color = Color("#f0a868")
		sky.ground_horizon_color = Color("#e8b07c")
		sky.ground_bottom_color = Color("#e8b07c")
	env.fog_light_color = Color("#e6b88a")
	sun.directional_shadow_max_distance = 140.0

func _dusk() -> void:
	# the Wyrm's hour: the sun all but gone (a cold low light), a deep blue-violet sky, the haze closing in; its
	# soul-fire (a teal glow, glow_light) lights the pit
	var d := Vector3(-1.0, 0.16, 0.25).normalized()
	var sun := _sun()
	sun.global_transform.basis = Basis.looking_at(-d)
	sun.light_color = Color("#8c9cff")
	sun.light_energy = 0.42
	var env := _env()
	var sky := env.sky.sky_material as ProceduralSkyMaterial if env.sky != null else null
	if sky != null:
		sky.sky_top_color = Color("#0b1024")
		sky.sky_horizon_color = Color("#3d2f58")
		sky.ground_horizon_color = Color("#2a2540")
		sky.ground_bottom_color = Color("#2a2540")
	env.ambient_light_color = Color("#5a6aa0")
	env.ambient_light_energy *= 0.55
	env.fog_light_color = Color("#2b3152")
	env.fog_depth_begin = 26.0
	env.fog_depth_end = 150.0
	env.tonemap_exposure *= 1.1

func _soul_light(p: Vector3, energy: float) -> void:
	if glow_light == null:
		glow_light = OmniLight3D.new()
		glow_light.light_color = Color("#7dffd0")
		glow_light.omni_range = 16.0
		glow_light.shadow_enabled = false
		mode.view.add_child(glow_light)
	glow_light.global_position = p
	glow_light.light_energy = energy

# ---------- staging ----------
func _stage() -> void:
	s = mode.sim
	sm = s.moba
	mode.set_render_scale(1.0)
	mode.hud.visible = false
	mode.view.fog_on = false
	sm.wave_at = INF
	for c in sm.camps:
		c.next = INF
	for id in BLUE:
		_ready_hero(id, str(BLUE[id]), 0)
	for id in RED:
		_ready_hero(id, str(RED[id]), 1)
	if run in ["pit", "rise", "roar", "roar2", "title"]:
		_dusk()
	elif run != "map":
		_golden()
	call("_stage_" + run)
	if mode.view._motes != null and not run in ["vista", "title"]:
		mode.view._motes.visible = false          # (pollen motes near the lens read as white blobs in close shots)
	mode.view.snap_camera()

func _ready_hero(id: String, hid: String, team: int) -> void:
	var u := _u(id)
	sm.swap_hero(u, hid)
	_level(u, 10)
	u.max_hp = float(s.stat(u, "hp"))
	u.hp = u.max_hp
	u.ult_cd = 0.0
	u.bot = false
	u.pos = PARK[team] + Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))
	u.move = Vector2.ZERO
	u.task = {}

func _minions(team: int, lane: int, kinds: Array, at: Vector2) -> Array:
	return sm.place_minions(team, lane, kinds, at)

# --- (a planning aid, not in the film: the Rift from straight above; MAPC=x,z,h for a closer look) ---
func _stage_map() -> void:
	var c := Vector3(0.0, 0.0, 0.0)
	var h := 400.0
	if OS.has_environment("MAPC"):
		var v := OS.get_environment("MAPC").split(",")
		c = Vector3(float(v[0]), 0.0, float(v[1]))
		h = float(v[2])
	_cam(0.0, 1.0, {"kind":"world", "e0":c + Vector3(0.0, h, 0.02 * h), "l0":c, "fov0":32.0})
	_env().fog_enabled = false
	mode.view.camera.far = h * 2.0

# --- "Two kingdoms.": over our castle at golden hour, down the middle lane to theirs on the horizon; the waves meeting
# in the lanes, heroes skirmishing in the river ---
func _stage_vista() -> void:
	var env := _env()
	env.fog_depth_begin = 70.0
	env.fog_depth_end = 340.0
	env.fog_density = 0.7
	for l in 3:
		_minions(0, l, ["melee", "melee", "melee", "caster", "caster", "caster"], sm.wp(0, l, 3) if l != 1 else Vector2(0.0, 26.0))
		_minions(1, l, ["melee", "melee", "melee", "caster", "caster", "caster"], sm.wp(1, l, 3) if l != 1 else Vector2(0.0, -26.0))
	var bp := [Vector2(-2.0, 9.0), Vector2(2.5, 10.0), Vector2(0.5, 12.0)]
	var rp := [Vector2(-1.5, -8.0), Vector2(2.0, -9.5), Vector2(0.0, -11.0)]
	var bi := ["b1", "b2", "b3"]
	var ri := ["r0", "r1", "r2"]
	for i in 3:
		_place(bi[i], bp[i], rp[i]).bot = true
		_place(ri[i], rp[i], bp[i]).bot = true
		_sturdy(bi[i])
		_sturdy(ri[i])
	_cam(0.0, 5.6, {"kind":"world", "e0":Vector3(-13.0, 35.0, 134.0), "l0":Vector3(0.0, 3.0, 42.0),
		"e1":Vector3(-3.0, 17.0, 97.0), "l1":Vector3(0.0, 2.0, -46.0), "fov0":52.0, "fov1":47.0, "lin":true})

# --- "One crown.": their King on his throne, a slow push in, low, the sun behind him ---
func _stage_kingred() -> void:
	for id in RED:
		_u(id).pos = Vector2(-38.0, -12.0) + Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))
	var k := Vector2(0.0, -99.0)
	_cam(0.0, 6.0, {"kind":"world", "e0":_g(Vector2(2.2, -90.5), 1.0), "l0":_g(k, 2.0),
		"e1":_g(Vector2(1.0, -94.2), 1.35), "l1":_g(k + Vector2(0.0, -0.4), 2.35), "fov0":42.0, "fov1":36.0, "lin":true})

# --- "Rally your team.": our five charge down the middle lane at the lens, in slow motion ---
func _stage_charge() -> void:
	var order := ["b4", "b3", "you", "b2", "b1"]          # Golem, Archmage, Knight, Dragoon, Stormcaller
	var xs := [-4.6, -2.3, 0.0, 2.3, 4.6]
	var zs := [1.6, 0.7, 0.0, 0.7, 1.6]
	for i in 5:
		var p := Vector2(xs[i], 47.0 + zs[i])
		_place(order[i], p, p + Vector2(0.0, -10.0))
		_walk(order[i], Vector2(0.0, -1.0), 4.6)
		_sturdy(order[i])
	_cam(0.0, 4.4, {"kind":"group", "ids":order, "e0":Vector3(2.6, 1.7, -8.6), "l0":Vector3(0.0, 1.2, 0.8),
		"e1":Vector3(-1.8, 1.5, -6.8), "l1":Vector3(0.0, 1.35, 0.6), "fov0":46.0, "fov1":42.0})

# --- the hit: both lines crash together in the river, every hero casting; time slows on the impact ---
func _stage_clash() -> void:
	var blue := ["b1", "b2", "you", "b3", "b4"]          # (the Golem at the far end: near the lens he hid the rest)
	var red := ["r2", "r3", "r0", "r1", "r4"]
	var xs := [-5.0, -2.5, 0.0, 2.5, 5.0]
	for i in 5:
		var bp := Vector2(xs[i], 9.0 + absf(xs[i]) * 0.15)
		var rp := Vector2(xs[i] * 0.95, -6.5 - absf(xs[i]) * 0.15)
		_place(blue[i], bp, rp)
		_place(red[i], rp, bp)
		_walk(blue[i], Vector2(0.0, -1.0), 5.0)
		_walk(red[i], Vector2(0.0, 1.0), 5.0)
		_sturdy(blue[i])
		_sturdy(red[i])
	# they meet about 1.2 s in: stop, and everyone throws what they've got, a beat apart
	_beat(1.0, _stop_all.bind(blue + red))
	var acts := ["a", "a", "w", "e", "q"]                 # (the two nearest the lens strike: a shield bubble hid them)
	for i in 5:
		_beat(1.02 + 0.05 * i, _face_cast.bind(blue[i], red[i], acts[i]))
		_beat(1.05 + 0.05 * i, _face_cast.bind(red[i], blue[i], acts[(i + 2) % 5]))
		_beat(1.9 + 0.07 * i, _face_cast.bind(blue[i], red[i], "a"))
		_beat(1.95 + 0.07 * i, _face_cast.bind(red[i], blue[i], "a"))
	_cam(0.0, 4.2, {"kind":"world", "e0":_g(Vector2(-13.0, 4.5), 4.2), "l0":_g(Vector2(0.0, 1.5), 0.6),
		"e1":_g(Vector2(-11.5, 0.5), 3.6), "l1":_g(Vector2(0.0, 0.5), 0.6), "fov0":42.0, "fov1":40.0,
		"shake_from":1.15})

# --- THUNDERSTORM: the Stormcaller's bolts on three of theirs ---
func _stage_storm() -> void:
	var c := Vector2(0.0, -16.0)
	var trio := ["r1", "r2", "r3"]
	var off := [Vector2(0.0, 0.0), Vector2(-2.0, -1.2), Vector2(2.0, -1.0)]
	for i in 3:
		_place(trio[i], c + off[i], c + Vector2(0.0, 12.0))
		_sturdy(trio[i])
	_place("b1", c + Vector2(0.5, 9.0), c)
	_beat(0.35, func(): _cast("b1", "r"))
	_cam(0.0, 4.0, {"kind":"orbit", "c":_g(c, 0.0), "r":8.5, "h":1.3, "a0":-0.45, "a1":0.05, "look_up":2.6})

# --- METEORS: the Archmage brings six down on four of theirs (over her shoulder, up the middle lane) ---
func _stage_meteor() -> void:
	var c := Vector2(-0.3, -41.0)
	var four := ["r0", "r4", "r1", "r3"]
	var off := [Vector2(0.0, 0.0), Vector2(-2.2, -0.8), Vector2(2.1, -0.6), Vector2(-0.4, -2.3)]
	for i in 4:
		_place(four[i], c + off[i], c + Vector2(0.0, 10.0))
	_place("b3", c + Vector2(-1.2, 10.5), c)
	set_meta("meteor_squad", four)
	_beat(0.3, func(): _cast("b3", "r"))
	_cam(0.0, 4.2, {"kind":"world", "e0":_g(c + Vector2(2.2, 16.0), 2.7), "l0":_g(c, 1.1),
		"e1":_g(c + Vector2(1.6, 14.4), 2.3), "l1":_g(c, 0.9), "fov0":46.0, "fov1":42.0, "shake_from":0.95})

# --- DRAGON DIVE: the Dragoon leaps off the ford onto their Barbarian (seen from the side, tracking him) ---
func _stage_dive() -> void:
	var tgt := Vector2(0.0, -17.5)
	_place("r0", tgt, tgt + Vector2(0.0, 6.0))
	_place("r4", tgt + Vector2(1.9, -1.4), tgt + Vector2(0.0, 6.0))
	_place("b2", tgt + Vector2(0.0, 10.0), tgt)
	set_meta("dive_squad", ["r0", "r4"])
	_beat(0.3, func(): _cast("b2", "r"))
	_cam(0.0, 3.6, {"kind":"track", "id":"b2", "eye":_g(tgt + Vector2(8.0, 4.5), 2.0), "l":Vector3(0.0, 1.2, 0.0),
		"fov0":46.0, "fov1":42.0, "shake_from":1.05})

# --- LANDSLIDE: the Golem rolls through three of theirs, at the lens, over the west ford ---
func _stage_slide() -> void:
	var start := Vector2(-46.0, 11.0)
	var three := ["r2", "r3", "r1"]
	var off := [Vector2(0.0, -4.0), Vector2(1.2, -5.6), Vector2(-1.1, -6.2)]
	for i in 3:
		_place(three[i], start + off[i], start)
	_place("b4", start, start + Vector2(0.0, -9.0))
	set_meta("slide_squad", three)
	_beat(0.3, func(): _cast("b4", "r"))
	_cam(0.0, 3.4, {"kind":"world", "e0":_g(start + Vector2(1.6, -13.5), 0.9), "l0":_g(start + Vector2(0.0, -3.0), 1.6),
		"e1":_g(start + Vector2(1.2, -12.5), 0.8), "l1":_g(start + Vector2(0.0, -5.0), 1.4), "fov0":50.0, "fov1":46.0,
		"shake_from":0.55})

# --- INFERNO: a ring of fire round the Mage, four of theirs thrown ---
func _stage_inferno() -> void:
	sm.swap_hero(_u("b3"), "mage")
	_u("b3").ult_cd = 0.0
	var c := Vector2(46.0, -14.0)
	_place("b3", c, c + Vector2(0.0, 6.0))
	var four := ["r0", "r4", "r3", "r1"]
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.5
		_place(four[i], c + Vector2.from_angle(a) * 3.2, c)
	_beat(0.3, func(): _cast("b3", "r"))
	_cam(0.0, 3.0, {"kind":"orbit", "c":_g(c, 0.0), "r":9.0, "h":2.0, "a0":1.2, "a1":1.75, "h1":4.5, "look_up":1.2})

# --- ARROW RAIN: an Archer's arrows pour down on three of theirs ---
func _stage_rain() -> void:
	sm.swap_hero(_u("b1"), "ranger")
	_u("b1").ult_cd = 0.0
	var c := Vector2(0.0, -17.0)
	var trio := ["r1", "r2", "r3"]
	var off := [Vector2(0.0, 0.0), Vector2(-2.0, -1.0), Vector2(2.0, -0.8)]
	for i in 3:
		_place(trio[i], c + off[i], c + Vector2(0.0, 10.0))
		_sturdy(trio[i])
	_place("b1", c + Vector2(0.3, 11.0), c)
	_beat(0.3, func(): _cast("b1", "r"))
	_cam(0.0, 4.0, {"kind":"world", "e0":_g(c + Vector2(6.5, 5.5), 1.9), "l0":_g(c, 1.8),
		"e1":_g(c + Vector2(5.5, 4.6), 1.7), "l1":_g(c, 1.4), "fov0":48.0, "fov1":44.0})

# --- LEGION: their Necromancer raises the dead in front of three of ours (over their shoulders, up the middle lane) ---
func _stage_legion() -> void:
	var c := Vector2(1.5, -24.0)
	_place("r1", c, c + Vector2(0.0, 10.0))
	var trio := {"you": Vector2(-0.4, 7.5), "b2": Vector2(-2.6, 8.6), "b4": Vector2(2.2, 8.8)}
	for id in trio:
		_place(id, c + (trio[id] as Vector2), c)
		_sturdy(id)
	_beat(0.3, func(): _cast("r1", "r"))
	_cam(0.0, 4.0, {"kind":"world", "e0":_g(c + Vector2(1.4, 14.0), 2.4), "l0":_g(c, 1.0),
		"e1":_g(c + Vector2(1.1, 12.6), 2.1), "l1":_g(c, 0.9), "fov0":44.0, "fov1":40.0})

# --- the icon come alive: our Knight and their Barbarian, sword on axe, in slow motion ---
func _stage_duel() -> void:
	var c := Vector2(0.0, -44.0)
	sm.swap_hero(_u("b1"), "knight")                   # (on a bot's seat: the player's own hero draws an aim line)
	_place("b1", c + Vector2(0.0, 1.15), c)
	_place("r0", c + Vector2(0.0, -1.15), c)
	_sturdy("b1")
	_sturdy("r0")
	_beat(0.35, _face_cast.bind("r0", "b1", "a"))
	_beat(0.42, _face_cast.bind("b1", "r0", "a"))
	_beat(1.6, _face_cast.bind("b1", "r0", "a"))
	_beat(1.7, _face_cast.bind("r0", "b1", "a"))
	_cam(0.0, 3.2, {"kind":"orbit", "c":_g(c, 0.0), "r":3.6, "h":1.0, "a0":-0.2, "a1":0.45, "h1":1.2, "look_up":1.15})

# --- "Break their towers.": their middle outer tower comes down, in slow motion ---
func _stage_tower() -> void:
	var tw := _red_tower(1, 1)
	var tp: Vector2 = tw.p
	tw.hp = float(tw.max_hp) * 0.85                    # (whole until it falls: its look follows its health)
	_place("you", tp + Vector2(-2.6, 2.5), tp)
	_place("b4", tp + Vector2(3.9, 1.3), tp)
	_place("b2", tp + Vector2(-0.4, 3.9), tp)
	for id in ["you", "b4", "b2"]:
		_sturdy(id)
	_minions(0, 1, ["melee", "melee", "caster", "caster"], tp + Vector2(1.0, 8.0))
	for k in [0.2, 0.6, 1.0, 1.35]:
		_beat(k, func(): _hit("you", tp))
		_beat(k + 0.12, func(): _hit("b4", tp))
		_beat(k + 0.2, func(): _hit("b2", tp))
	_beat(1.55, func(): sm.hit_tower(_u("you"), int(tw.id), float(tw.max_hp) * 2.0, _u("you").pos))
	_cam(0.0, 4.6, {"kind":"world", "e0":_g(tp + Vector2(5.2, 10.6), 1.3), "l0":_g(tp, 3.8),
		"e1":_g(tp + Vector2(4.6, 9.4), 1.2), "l1":_g(tp, 3.2), "fov0":46.0, "fov1":42.0, "shake_from":1.55})

func _red_tower(lane: int, tier: int) -> Dictionary:
	for tw in sm.towers:
		if int(tw.team) == 1 and int(tw.lane) == lane and int(tw.tier) == tier:
			return tw
	return {}

# --- "Topple their King.": their keep open, four of ours on the King; he slams back ---
func _stage_kingfight() -> void:
	for tw in sm.towers:
		if int(tw.team) == 1 and (int(tw.lane) == 1 or int(tw.tier) == 4):
			tw.hp = 0.0
			tw.dead = true
	for g in s.gates:
		if int(g.team) == 1 and int(g.get("lane", 1)) == 1:
			g.hp = 0.0
	(sm.kings[1] as Dictionary).hp = float((sm.kings[1] as Dictionary).max_hp) * 0.6
	for id in RED:
		_u(id).pos = Vector2(-38.0, -12.0) + Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))
	var king := Vector2(0.0, -99.0)
	var spots := {"you": Vector2(-2.3, 1.9), "b4": Vector2(2.7, 1.5), "b2": Vector2(-3.1, -0.3), "b1": Vector2(3.8, 4.6)}
	for id in spots:
		_place(id, king + (spots[id] as Vector2), king)
		_sturdy(id)
	for k in [0.15, 0.55, 0.95, 1.35, 1.75, 2.15, 2.55, 2.95, 3.35, 3.75, 4.15]:
		_beat(k, func(): _hit("you", king))
		_beat(k + 0.1, func(): _hit("b4", king))
		_beat(k + 0.2, func(): _hit("b2", king))
		_beat(k + 0.05, func(): _hit("b1", king))
	# one slow push in on him from in front, low, between our heroes (the edit takes two stretches of it)
	_cam(0.0, 5.4, {"kind":"world", "e0":_g(king + Vector2(1.5, 8.6), 1.7), "l0":_g(king, 2.0),
		"e1":_g(king + Vector2(0.8, 5.4), 1.3), "l1":_g(king, 2.3), "fov0":46.0, "fov1":40.0})

# --- "Topple their King.": their middle gate smashed in, our five pouring through it toward their King on his throne
# (no blows on him: the King has no fight animations, Kevin: "it looks weird") ---
var routes := {}                # id -> [waypoints], walked one after another at its speed (m/s): [points, speed]

func _stage_breach() -> void:
	for tw in sm.towers:
		if int(tw.team) == 1 and int(tw.lane) == 1:
			tw.hp = 0.0                                    # (a gate behind a standing tower can't be hurt)
			tw.dead = true
	var gate := {}
	for g in s.gates:
		if int(g.team) == 1 and int(g.get("lane", -1)) == 1:
			gate = g
	gate.hp = float(gate.max_hp) * 0.2
	var gc: Vector2 = gate.c
	set_meta("gate", int(gate.id))
	sm.swap_hero(_u("b1"), "knight")                   # (the Knight on a bot's seat: the player's own hero draws an aim
	sm.swap_hero(_u("you"), "stormcaller")             # line when he strikes; you are the Stormcaller here, behind)
	var front := {"b1": Vector2(-1.5, 2.1), "b4": Vector2(1.8, 2.0), "b2": Vector2(0.1, 3.3), "you": Vector2(-3.0, 5.6),
		"b3": Vector2(3.0, 5.9)}
	for id in front:
		_place(id, gc + (front[id] as Vector2), gc)
		_sturdy(id)
	for k in [0.1, 0.4, 0.7]:
		_beat(k, func(): _hit("b1", gc))
		_beat(k + 0.08, func(): _hit("b4", gc))
		_beat(k + 0.15, func(): _hit("b2", gc))
	_beat(0.9, func(): s._damage_gate(_u("b4"), s.gates[int(get_meta("gate"))], 99999.0))
	# through the gate, two abreast, then fanning out up the courtyard toward the throne
	var king := Vector2(0.0, -99.0)
	var inside := {"b1": Vector2(-1.2, -9.0), "b4": Vector2(1.6, -8.4), "b2": Vector2(0.2, -11.0), "you": Vector2(-3.2, -7.0),
		"b3": Vector2(3.4, -7.4)}
	var order := ["b1", "b4", "b2", "you", "b3"]
	for i in order.size():
		var id: String = order[i]
		_beat(1.25 + 0.12 * i, _route.bind(id, [gc + Vector2(-0.6 if i % 2 == 0 else 0.6, 0.5), gc + Vector2(0.0, -2.0),
			gc + (inside[id] as Vector2)], 5.0))
	_cam(0.0, 5.2, {"kind":"world", "e0":_g(gc + Vector2(2.4, 10.5), 2.3), "l0":_g(gc + Vector2(0.0, -5.0), 1.8),
		"e1":_g(gc + Vector2(1.0, 4.6), 1.9), "l1":_g(king, 2.0), "fov0":48.0, "fov1":44.0, "shake_from":0.9})

func _route(id: String, pts: Array, speed: float) -> void:
	routes[id] = [pts, speed]

func _walk_routes() -> void:
	for id in routes.keys():
		var u := _u(id)
		if not s.alive(u):
			continue
		var pts: Array = routes[id][0]
		while pts.size() > 1 and (u.pos as Vector2).distance_to(pts[0]) < 0.8:
			pts.remove_at(0)
		var to: Vector2 = (pts[0] as Vector2) - (u.pos as Vector2)
		if pts.size() == 1 and to.length() < 0.4:
			routes.erase(id)
			walkers.erase(id)
			u.move = Vector2.ZERO
			if id == "you":
				mode.hud._stick_active = false
			continue
		walkers[id] = to.normalized() * minf(1.0, float(routes[id][1]) / maxf(0.1, float(s.stat(u, "speed"))))
		_face(id, pts[0])

# --- "But deep in its pit...": dusk; three of ours at the pit's north mouth, the ground beginning to shake ---
func _stage_pit() -> void:
	var trio := {"you": Vector2(0.0, 9.6), "b2": Vector2(-1.9, 10.6), "b3": Vector2(1.9, 10.8)}
	for id in trio:
		_place(id, PIT + (trio[id] as Vector2), PIT)
		_sturdy(id)
	_soul_light(_g(PIT, 0.6), 1.2)
	_cam(0.0, 5.0, {"kind":"world", "e0":_g(PIT + Vector2(0.9, 19.5), 1.6), "l0":_g(PIT, 1.0),
		"e1":_g(PIT + Vector2(0.5, 15.5), 1.3), "l1":_g(PIT, 0.9), "fov0":44.0, "fov1":40.0, "shake_from":3.2})

# --- "...the Grave Wyrm wakes.": it rises out of its pit, seen from the ground, slowed ---
func _stage_rise() -> void:
	var trio := {"you": Vector2(0.0, 9.6), "b2": Vector2(-1.9, 10.6), "b3": Vector2(1.9, 10.8)}
	for id in trio:
		_place(id, PIT + (trio[id] as Vector2), PIT)
		_sturdy(id)
	_soul_light(_g(PIT, 0.4), 1.2)
	_wyrm_at(0.25)
	_cam(0.0, 4.4, {"kind":"world", "e0":_g(PIT + Vector2(-1.2, 7.0), 0.45), "l0":_g(PIT, 1.4),
		"e1":_g(PIT + Vector2(-1.0, 6.3), 0.4), "l1":_g(PIT, 4.6), "fov0":54.0, "fov1":50.0, "shake_from":0.3})

# --- the climax: it rears up and roars, pouring its soul-fire at them (roar: between our heroes; roar2: low in front of
# it, the soul-fire pouring at the lens). Up from the staging (its rise is over by 2.2 s), the breath at 2.4 ---
func _stage_roar() -> void:
	var trio := {"you": Vector2(-0.6, 8.2), "b2": Vector2(-3.8, 9.0), "b3": Vector2(1.6, 9.6)}
	for id in trio:
		_place(id, PIT + (trio[id] as Vector2), PIT)
		_sturdy(id)
	_soul_light(_g(PIT, 2.0), 1.6)
	_wyrm_at(0.0)
	_beat(2.4, _breath)
	_cam(0.0, 5.6, {"kind":"world", "e0":_g(PIT + Vector2(-3.2, 11.4), 1.2), "l0":_g(PIT + Vector2(0.3, 0.5), 3.5),
		"e1":_g(PIT + Vector2(-3.0, 10.6), 1.1), "l1":_g(PIT + Vector2(0.3, 0.5), 4.0), "fov0":40.0, "fov1":36.0,
		"shake_from":2.45})

func _stage_roar2() -> void:
	var trio := {"you": Vector2(-0.6, 8.2), "b2": Vector2(-3.8, 9.0), "b3": Vector2(1.6, 9.6)}
	for id in trio:
		_place(id, PIT + (trio[id] as Vector2), PIT)
		_sturdy(id)
	_soul_light(_g(PIT, 2.0), 1.6)
	_wyrm_at(0.0)
	_beat(2.4, _breath)
	_cam(0.0, 5.6, {"kind":"world", "e0":_g(PIT + Vector2(0.9, 6.6), 0.9), "l0":_g(PIT + Vector2(0.0, 1.4), 4.0),
		"e1":_g(PIT + Vector2(0.7, 6.2), 0.8), "l1":_g(PIT + Vector2(0.0, 1.4), 4.6), "fov0":58.0, "fov1":54.0,
		"shake_from":2.45})

# --- the title: black; the lightning rift splits the dark (cue B's first hit, TITLE_A); FATE and BOUND fly in from the
# viewer and slam home round it with the crown (its second hit, TITLE_B): a flash, the shake, the flags whipping, the
# rift flaring, light rays turning behind; the tagline; the Rift at dusk below, dimmed, the Wyrm's glow in its pit ---
const TitleLogo = preload("res://scripts/app/title_logo.gd")
const RaysShader = preload("res://scripts/app/title_rays.gdshader")
const GlintShader = preload("res://scripts/app/title_glint.gdshader")
const TITLE_A := 1.0                    # the rift (cue B at 0.0)
const TITLE_B := 3.0                    # the slam (cue B at 3.9, its quiet middle cut: 2.0 s after the lightning)
const TITLE_FLIGHT := 0.32
const TITLE_W := 1180.0                 # the title's width on a 1920 x 1080 frame
const TITLE_Y := 0.40                   # its middle, this far down
const TAG_AT := 1.7                     # the tagline, this long after the slam
const TITLE_CRACKS := [[1.6, 0.7], [2.3, 0.9]]   # the rift crackling alone: [time, strength]
var tl: Dictionary = {}

func _stage_title() -> void:
	_wyrm_at(0.0)
	_soul_light(_g(PIT, 2.0), 1.6)
	_cam(0.0, 9.8, {"kind":"world", "e0":Vector3(50.0, 30.0, 44.0), "l0":_g(PIT, 0.0),
		"e1":Vector3(46.0, 27.5, 38.5), "l1":_g(PIT + Vector2(-5.0, -2.5), 0.0), "fov0":46.0, "lin":true})
	var vp: Vector2 = root.get_visible_rect().size
	var k := vp.x / 1920.0
	var layer := CanvasLayer.new()
	layer.layer = 50
	root.add_child(layer)
	var stage := Control.new()
	stage.size = vp
	stage.pivot_offset = vp * 0.5
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(stage)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 1.0)
	dim.size = vp
	stage.add_child(dim)
	var white := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	var rays := TextureRect.new()
	rays.texture = ImageTexture.create_from_image(white)
	rays.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rays.stretch_mode = TextureRect.STRETCH_SCALE
	var rs := TITLE_W * vp.x / 1920.0 * 2.1
	rays.size = Vector2(rs, rs)
	rays.position = Vector2(vp.x * 0.5, vp.y * TITLE_Y) - rays.size * 0.5
	var rm := ShaderMaterial.new()
	rm.shader = RaysShader
	rays.material = rm
	rm.set_shader_parameter("power", 0.0)
	stage.add_child(rays)
	var logo = TitleLogo.new(false)
	var lw := TITLE_W * k
	logo.size = Vector2(lw, lw * TitleLogo.aspect())
	logo.position = Vector2(vp.x * 0.5 - lw * 0.5, vp.y * TITLE_Y - logo.size.y * 0.5)
	logo.pivot_offset = logo.size * 0.5
	stage.add_child(logo)
	var gm := ShaderMaterial.new()
	gm.shader = GlintShader
	logo.set_shine(gm)
	var tag := Label.new()
	tag.text = "5V5 HERO BATTLES"
	var ls := LabelSettings.new()
	ls.font = load("res://assets/fonts/LilitaOne-Regular.ttf")
	ls.font_size = int(78 * k)
	ls.font_color = Color.WHITE
	ls.outline_size = int(14 * k)
	ls.outline_color = Color("#080e1e")
	ls.shadow_size = int(10 * k)
	ls.shadow_color = Color(0, 0, 0, 0.6)
	tag.label_settings = ls
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.size = Vector2(vp.x, 110.0 * k)
	tag.position = Vector2(0.0, logo.position.y + logo.size.y + 6.0 * k)
	tag.modulate.a = 0.0
	stage.add_child(tag)
	var grad := Gradient.new()
	grad.set_color(0, Color("#5aaaff"))
	grad.set_color(1, Color("#ff7828"))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 512
	gt.height = 8
	var bar := TextureRect.new()
	bar.texture = gt
	bar.stretch_mode = TextureRect.STRETCH_SCALE
	bar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bar.size = Vector2(560.0 * k, 9.0 * k)
	bar.position = Vector2(vp.x * 0.5 - bar.size.x * 0.5, tag.position.y + 108.0 * k)
	bar.modulate.a = 0.0
	stage.add_child(bar)
	var flash := ColorRect.new()
	flash.color = Color(1.0, 0.97, 0.9, 0.0)
	flash.size = vp
	stage.add_child(flash)
	tl = {"stage": stage, "dim": dim, "rays": rm, "logo": logo, "glint": gm, "tag": tag, "bar": bar, "flash": flash,
		"a": false, "b": false, "shake": 0.0, "punch": 0.0, "tag_y": tag.position.y, "bar_y": bar.position.y}
	# the rift alone first: the word, the crown and the flags come in on the slam
	for n in [logo._base, logo.flag_l, logo.flag_r]:
		(n as CanvasItem).modulate.a = 0.0
	logo.rift.modulate.a = 0.0

func _title_step(delta: float) -> void:
	if tl.is_empty():
		return
	var logo = tl.logo
	var flash: ColorRect = tl.flash
	var dim: ColorRect = tl.dim
	if t >= TITLE_A and not bool(tl.a):
		tl.a = true
		flash.color.a = 0.85
		logo.rift.modulate.a = 1.0
		logo.rift.burst(1.0)
		tl.shake = 0.5
		printerr("TITLE_A t=%.3f" % t)
	if bool(tl.a):
		dim.color.a = lerpf(1.0, 0.5, clampf((t - TITLE_A) / 1.2, 0.0, 1.0))
		var ci := int(tl.get("crack", 0))
		if ci < TITLE_CRACKS.size() and t >= float(TITLE_CRACKS[ci][0]):
			var k := float(TITLE_CRACKS[ci][1])
			logo.rift.burst(k)
			flash.color.a = maxf(flash.color.a, 0.22 * k)
			tl.shake = maxf(float(tl.shake), 0.3 * k)
			tl["crack"] = ci + 1
	var fly0 := TITLE_B - TITLE_FLIGHT
	if t >= fly0 and not bool(tl.b):
		var p := clampf((t - fly0) / TITLE_FLIGHT, 0.0, 1.0)
		var e := p * p
		for n in [logo._base, logo.flag_l, logo.flag_r]:
			(n as CanvasItem).modulate.a = clampf(p * 3.0, 0.0, 1.0)
		logo.scale = Vector2.ONE * lerpf(3.2, 1.0, e)
		logo.rotation = lerpf(-0.18, 0.0, e)
		if t >= TITLE_B:
			tl.b = true
			logo.scale = Vector2.ONE
			logo.rotation = 0.0
			for n in [logo._base, logo.flag_l, logo.flag_r]:
				(n as CanvasItem).modulate.a = 1.0
			logo.kick(32.0)
			flash.color.a = 0.95
			tl.shake = 1.0
			tl.punch = 1.0
			printerr("TITLE_B t=%.3f" % t)
	if bool(tl.b):
		var s2 := t - TITLE_B
		var bounce := exp(-s2 * 9.0) * cos(s2 * 34.0)
		logo.scale = Vector2(1.0 + 0.06 * bounce, 1.0 - 0.06 * bounce)
		(tl.rays as ShaderMaterial).set_shader_parameter("power", 0.42 * smoothstep(0.05, 0.9, s2))
		(tl.rays as ShaderMaterial).set_shader_parameter("spin", t * 0.22)
		var g := s2 - 1.2
		var sweep := -1.0
		if g >= 0.0 and fmod(g, 4.5) < 0.8:
			sweep = lerpf(-0.15, 1.15, fmod(g, 4.5) / 0.8)
		(tl.glint as ShaderMaterial).set_shader_parameter("sweep", sweep)
		var tg := clampf((s2 - TAG_AT) / 0.6, 0.0, 1.0)
		var te := 1.0 - (1.0 - tg) * (1.0 - tg)
		(tl.tag as Label).modulate.a = te
		(tl.tag as Label).position.y = float(tl.tag_y) + 18.0 * (1.0 - te)
		(tl.bar as TextureRect).modulate.a = clampf((s2 - TAG_AT - 0.25) / 0.5, 0.0, 1.0)
	flash.color.a = maxf(0.0, flash.color.a - delta * 3.0)
	tl.shake = maxf(0.0, float(tl.shake) - delta * 2.4)
	tl.punch = maxf(0.0, float(tl.punch) - delta * 2.8)
	var amp := 18.0 * float(tl.shake) * float(tl.shake)
	var st: Control = tl.stage
	st.position = Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
	st.scale = Vector2.ONE * (1.0 + 0.05 * float(tl.punch) * float(tl.punch))

func _wyrm_at(delay: float) -> void:
	for c in sm.camps:
		if str(c.kind) == "wyrm":
			c.next = s.time + delay

func _wyrm() -> Dictionary:
	return sm._wyrm_unit()

func _breath() -> void:
	var wy := _wyrm()
	if wy.is_empty():
		printerr("NO WYRM")
		return
	var me := _u("you")
	var bd: Vector2 = ((me.pos as Vector2) - (wy.pos as Vector2)).normalized()
	wy.face = Sim.angle_of(bd)
	mode.view.on_event({"k":"wyrm_breath", "id":wy.id, "pos":wy.pos, "dir":bd, "n":0})
	set_meta("breathing", true)
	_beat(t + 1.5, func(): remove_meta("breathing"))
	printerr("BREATH t=%.3f" % t)

# ---------- every frame ----------
func _slow(tt: float) -> float:
	var keys: Array = SCALE.get(run, [])
	if keys.is_empty() or tt < float(keys[0][0]):
		return 1.0
	for i in keys.size() - 1:
		if tt >= float(keys[i][0]) and tt < float(keys[i + 1][0]):
			var k := (tt - float(keys[i][0])) / maxf(0.0001, float(keys[i + 1][0]) - float(keys[i][0]))
			return lerpf(float(keys[i][1]), float(keys[i + 1][1]), k)
	return float(keys[keys.size() - 1][1])

func _shake(amount: float) -> Vector3:
	return Vector3(sin(t * 23.0) + 0.5 * sin(t * 51.0 + 1.3), 0.6 * sin(t * 29.0 + 0.7) + 0.3 * sin(t * 61.0), cos(t * 19.0 + 2.1)) * amount

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
		printerr("CAMSEG %d %s frame %d t=%.3f" % [cam_seg, spec.kind, frames - rec0, t])
	var u := clampf((t - float(seg[0])) / maxf(0.001, float(seg[1]) - float(seg[0])), 0.0, 1.0)
	if not bool(spec.get("lin", false)):
		u = _ease(u)
	var eye := Vector3.ZERO
	var look := Vector3.ZERO
	var fov := lerpf(float(spec.get("fov0", 50.0)), float(spec.get("fov1", spec.get("fov0", 50.0))), u)
	match str(spec.kind):
		"world":
			eye = (spec.e0 as Vector3).lerp(spec.get("e1", spec.e0), u)
			look = (spec.l0 as Vector3).lerp(spec.get("l1", spec.l0), u)
		"group":
			var sum := Vector3.ZERO
			var n := 0
			for id in spec.ids:
				var a := _actor(str(id))
				if not a.is_empty() and s.alive(_u(str(id))):
					sum += (a.root as Node3D).position
					n += 1
			if n > 0:
				set_meta("grp", sum / float(n))
			var base: Vector3 = get_meta("grp", Vector3.ZERO)
			eye = base + (spec.e0 as Vector3).lerp(spec.e1, u)
			look = base + (spec.l0 as Vector3).lerp(spec.l1, u)
		"track":
			var at := _actor(str(spec.id))
			var tp: Vector3 = (at.root as Node3D).position if not at.is_empty() else _g(_u(str(spec.id)).pos)
			eye = spec.eye
			look = tp + (spec.l as Vector3)
		"orbit":
			var ang := lerpf(float(spec.a0), float(spec.a1), u)
			var c: Vector3 = spec.c
			var h := lerpf(float(spec.h), float(spec.get("h1", spec.h)), u)
			eye = c + Vector3(cos(ang) * float(spec.r), h, sin(ang) * float(spec.r))
			look = c + Vector3(0.0, float(spec.get("look_up", 1.0)), 0.0)
	var sh := float(spec.get("shake", 0.0))
	if spec.has("shake_from") and t >= float(spec.shake_from):
		sh = maxf(sh, 0.16 * exp(-(t - float(spec.shake_from)) * 2.2))
	if sh > 0.0:
		eye += _shake(sh)
		look += _shake(sh * 0.6)
	mode.view.cam_override = [eye, look]
	mode.view.camera.fov = fov

func _specials() -> void:
	# the meteors, the dive and the slide throw the ones they hit (dead, flying)
	if has_meta("meteor_squad"):
		for m in s.meteors:
			if not m.has("seen") and s.time >= float(m.t_hit) - 0.01:
				m["seen"] = true
				for id in get_meta("meteor_squad"):
					var o := _u(id)
					if s.alive(o) and (o.pos as Vector2).distance_to(m.at) < 3.4:
						_kill(id, m.at, 7.0 + randf() * 3.0, 7.5 + randf() * 3.0, "b3")
	for key in ["dive_squad", "slide_squad"]:
		if has_meta(key):
			var who := "b2" if key == "dive_squad" else "b4"
			for id in get_meta(key):
				var o2 := _u(id)
				var hk := "hp_" + str(id)
				var was := float(get_meta(hk, o2.hp))
				set_meta(hk, o2.hp)
				if s.alive(o2) and float(o2.hp) < was - 1.0:
					_kill(id, _u(who).pos, 8.0 + randf() * 2.0, 6.5 + randf() * 2.0, who)
	var wy0 := _wyrm()
	if not wy0.is_empty() and not has_meta("wyrm_faced"):
		set_meta("wyrm_faced", true)                    # (facing our heroes, north)
		var nf := Sim.angle_of(Vector2(0.0, 1.0))
		wy0.face = nf
		wy0["home_face"] = nf
		printerr("WYRM UP t=%.3f" % t)
	if not wy0.is_empty() and not has_meta("wyrm_rose") and run != "title" and not (run in ["roar", "roar2"] and t > 0.5):
		var wa := _actor(str(wy0.id))
		if not wa.is_empty() and wa.get("player") != null:
			set_meta("wyrm_rose", true)                    # (made while the fog still hid it, it would come up already up)
			mode.view._play(wa, "w/Rise", 1.0, 1.6)
			printerr("WYRM RISE t=%.3f" % t)
	if glow_light != null:
		var wy := _wyrm()
		if not wy.is_empty():
			var a := _actor(str(wy.id))
			if not a.is_empty():
				glow_light.global_position = (a.root as Node3D).position + Vector3(0.0, 3.0, 1.2)
				glow_light.light_energy = 2.2 + 0.4 * sin(t * 9.0) + (2.5 if has_meta("breathing") else 0.0)

func _process(delta: float) -> bool:
	frames += 1
	if not staged:
		if mode.sim == null or not mode._build_queue.is_empty() or frames < 40 or not mode._warm.is_empty():
			return false
		_stage()
		staged = true
		rec0 = frames
		printerr("REC_START %d" % frames)
		return false
	_quiet()
	t += delta
	Engine.time_scale = _slow(t)
	for b in beats.duplicate():
		if t >= float(b[0]):
			beats.erase(b)
			(b[1] as Callable).call()
	_apply_cam()
	_walk_routes()
	for id in walkers:
		var wu := _u(id)
		if s.alive(wu):
			wu.move = walkers[id]
	_drive_you()
	_reveal_all()
	for tw in sm.towers:
		tw.next = s.time + 99.0                         # (no tower fire: shots from off screen are just noise)
	_keep_sturdy()
	_specials()
	_hide_rings()
	_title_step(delta)
	for kn in mode.view.oracle_nodes:
		if (kn as Dictionary).get("ground") != null:
			(kn.ground as Node3D).visible = false          # (the Kings' rings too)
	if (frames - rec0) % 3 == 0:
		printerr("TT %d %.3f" % [frames - rec0, t])
	if not snaps.is_empty() and t >= float(snaps[0]):
		var at := float(snaps.pop_front())
		root.get_texture().get_image().save_png("%s/snap_%s_%.2f.png" % [out_dir, run, at])
		printerr("SNAP %s %.2f" % [run, at])
		if snaps.is_empty():
			printerr("SHOT_DONE %s snaps" % run)
			quit(0)
	if t >= float(LENGTH[run]) or (until > 0.0 and t >= until):
		printerr("SHOT_DONE %s %d frames t=%.2f" % [run, frames - rec0, t])
		quit(0)
	return false
