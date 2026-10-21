extends SceneTree
# 0.31.200 (Kevin: "Need all new pics for app stores"): the store screenshots' match moments -- the real 5v5 on the
# Rift (siege_mode.gd, offline against bots, never the live server), staged: who stands where, at what level, who casts
# what and when; the bots fight it out on their own in between. With the HUD as you see it, or (CINE=1) none and a
# camera of the scene's own. One scene a process; the picture is saved and the process ends.
#   SCENE=teamfight|ult|wyrm|tower|king|feature  OUT=<png>  [HERO=<id>] [CINE=1] [AT=<frames after staging>]
#   DISPLAY=:97 FB_FORCE_HQ=1 godot --rendering-method mobile --fixed-fps 30 --resolution 1080x2400 --path . \
#     -s res://tools/store4_match.gd
# The 3D is drawn at full resolution (the phone's is 50 %: siege_mode RENDER_SCALE) for a sharp picture.
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")

var mode
var frames := 0
var scene := "teamfight"
var out := "/tmp/store4.png"
var cine := false
var staged := -1                     # the frame it was staged on
var at := 75                         # the shot, frames after staging
var cam: Array = []
var _plan: Array = []                # [frames after staging, method, [args]]
var _shot := false

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")
	scene = OS.get_environment("SCENE") if OS.has_environment("SCENE") else scene
	out = OS.get_environment("OUT") if OS.has_environment("OUT") else out
	cine = OS.get_environment("CINE") == "1"
	mode = Mode.new()
	mode.moba_hero = OS.get_environment("HERO") if OS.has_environment("HERO") else _hero_for(scene)
	mode.match_seed = int(OS.get_environment("SEED")) if OS.has_environment("SEED") else 2026
	root.add_child(mode)
	RenderingServer.frame_post_draw.connect(func():
		if staged >= 0 and frames == staged + at and not _shot:
			_shot = true
			root.get_texture().get_image().save_png(out)
			print("STORE4_SHOT ", scene, " ", out)
			_quit_soon())

func _quit_soon() -> void:
	await process_frame
	quit(0)

static func _hero_for(sc: String) -> String:
	match sc:
		"ult":
			return "archmage"
		"wyrm":
			return "dragoon"
		"tower":
			return "golem"
		"king":
			return "berserker"
	return "stormcaller"

func s():
	return mode.sim

func _heroes(team: int) -> Array:
	var outv := []
	for u in s().units:
		if bool(u.get("hero", false)) and int(u.team) == team:
			outv.append(u)
	return outv

func _level(u: Dictionary, lv: int) -> void:
	lv = mini(lv, int(s().moba.LEVEL_MAX))          # (past the cap the loop never ends: the Wyrm and King scenes hung)
	while int(u.level) < lv:
		s().moba.add_xp(u, s().moba.need(int(u.level)))
	u.picks = []

func _place(u: Dictionary, p: Vector2, face_to: Vector2) -> void:
	u.pos = p
	u.move = Vector2.ZERO
	u.task = {}
	u.face = s().angle_of((face_to - p).normalized())

func _tough(u: Dictionary, k := 5.0, frac := 1.0) -> void:
	u.max_hp = float(u.max_hp) * k
	u.hp = float(u.max_hp) * frac

func _cast(id: String, what: String) -> void:
	match what:
		"q":
			s().act(id, "ability")
		"r":
			s().act(id, "ult")
		"a":
			s().act(id, "attack")
		_:
			s().act(id, "spell", what)

func _face(id: String, to: Vector2) -> void:
	var u: Dictionary = s().by_id[id]
	u.face = s().angle_of((to - (u.pos as Vector2)).normalized())

func _face_unit(id: String, other: String) -> void:
	_face(id, s().by_id[other].pos)

func _hit(id: String, at_p: Vector2) -> void:
	_face(id, at_p)
	_cast(id, "a")

func _waves_off() -> void:
	s().moba.wave_at = INF

func _wyrm_breath() -> void:
	var wy: Dictionary = s().moba._wyrm_unit()
	if wy.is_empty():
		return
	var me: Dictionary = s().by_id["you"]
	var bd: Vector2 = ((me.pos as Vector2) - (wy.pos as Vector2)).normalized()
	mode.view.on_event({"k":"wyrm_breath", "id":wy.id, "pos":wy.pos, "dir":bd, "n":0})

func _process(_delta: float) -> bool:
	frames += 1
	if mode.sim == null or not mode._build_queue.is_empty() or frames < 40:
		return false
	if staged < 0:
		_stage()
		staged = frames
		if OS.has_environment("AT"):
			at = int(OS.get_environment("AT"))
		return false
	var k := frames - staged
	if OS.has_environment("TRACE") and k % 10 == 0:
		print("STORE4 trace k=", k, " t=", snapped(float(s().time), 0.01))
	if k < 30:
		_quiet()
	for p in _plan:
		if int(p[0]) == k:
			callv(str(p[1]), (p[2] if p.size() > 2 else []) as Array)
	if not cam.is_empty():
		mode.view.cam_override = cam
	if k == at - 1:
		for u in s().units:
			if bool(u.get("hero", false)):
				print("STORE4 hero ", u.id, " ", u.get("hero_id", u.get("cls", "")), " at ", u.pos, " hp ", int(u.hp), "/", int(u.max_hp))
	if frames > staged + at + 30:
		quit(0)
	return false

# the names over the heroes as in an online match (sample names and clan tags: never the server's players)
const NAMES := {"you": ["Midblade", "WOLF", "3.5.1"], "b1": ["Ironclad", "WOLF", "3.5.1"], "b2": ["Mirabel", "", ""],
	"b3": ["Thornwick", "WOLF", "3.5.1"], "b4": ["Kaelen", "", ""], "r0": ["Pyra", "EMBR", "6.2.4"], "r1": ["Grimwald", "EMBR", "6.2.4"],
	"r2": ["Vex", "", ""], "r3": ["Odessa", "EMBR", "6.2.4"], "r4": ["Brannoc", "", ""]}

func _dress() -> void:
	# mid-match: 9 minutes in, the kills, your gold and items, everyone's names (the toasts of the staging cleared)
	if OS.get_environment("NOTIME") != "1":
		s().time = 540.0
	s().kills = [14, 11]
	var me: Dictionary = s().by_id["you"]
	me.gold = 1285.0
	me.items = ["archon", "greaves", "titan"]
	me.kills = 5
	var v = mode.view
	mode.hud.player_name = str(NAMES.you[0])
	v.my_name = str(NAMES.you[0])
	v.my_tag = str(NAMES.you[1])
	v.my_crest = str(NAMES.you[2])
	for id in NAMES:
		if id == "you" or not s().by_id.has(id):
			continue
		v.player_names[id] = str(NAMES[id][0])
		mode.hud.net_names[id] = str(NAMES[id][0])
		if str(NAMES[id][1]) != "":
			v.player_tags[id] = str(NAMES[id][1])
			v.player_crests[id] = str(NAMES[id][2])

func _quiet() -> void:
	mode.hud._toast = ""

func _stage() -> void:
	mode.set_render_scale(1.0)
	_dress()
	var sm = s().moba
	sm.wave_at = INF
	for c in sm.camps:
		c.next = INF
	print("STORE4 ids ", s().by_id.keys())
	match scene:
		"teamfight", "feature", "fight":
			_stage_teamfight()
		"ult":
			_stage_ult()
		"wyrm":
			_stage_wyrm()
		"tower":
			_stage_tower()
		"king":
			_stage_king()
	if cine:
		mode.hud.visible = false                     # (the camera's own far plane: the whole field in view hung lavapipe)

# ---- the scenes ----
func _stage_teamfight() -> void:
	# two lines meeting in the river, everyone level 9, posed (not left to the bots, who'd pile into one heap): each hero
	# swings or casts at the one across from him, a beat apart, and you (the Stormcaller) bring down your storm
	var blue := _heroes(0)
	var red := _heroes(1)
	var bp := [Vector2(-5.2, 5.6), Vector2(-1.9, 4.9), Vector2(2.3, 5.1), Vector2(5.6, 5.8)]
	var rp := [Vector2(-5.0, 0.4), Vector2(-1.6, -0.6), Vector2(1.8, 0.2), Vector2(5.2, -0.4), Vector2(0.2, -3.6)]
	var j := 0
	var pairs := []
	for i in blue.size():
		var u: Dictionary = blue[i]
		_level(u, 9)
		_tough(u, 6.0, 0.5 + 0.12 * float(i % 4))
		u.bot = false
		if str(u.id) != "you":
			_place(u, bp[j], rp[j])
			pairs.append([str(u.id), rp[j]])
			j += 1
	for i in red.size():
		var u: Dictionary = red[i]
		_level(u, 9)
		_tough(u, 6.0, 0.4 + 0.12 * float(i % 4))
		u.bot = false
		_place(u, rp[i], bp[mini(i, 3)])
		if scene == "teamfight" and (i == 1 or i == 2):
			u.hp = 1.0                                   # (your storm finishes these two: a DOUBLE KILL)
		pairs.append([str(u.id), bp[mini(i, 3)]])
	var me: Dictionary = s().by_id["you"]
	_place(me, Vector2(0.3, 8.8), Vector2(0.0, -0.4))
	var acts := ["q", "a", "w", "e", "a", "q", "w", "a", "e"]
	_plan = []
	for i in pairs.size():
		var f := 8 + 5 * i
		_plan.append([f, "_face", [str(pairs[i][0]), pairs[i][1]]])
		_plan.append([f + 1, "_cast", [str(pairs[i][0]), acts[i % acts.size()]]])
	_plan.append([30, "_face", ["you", Vector2(-1.0, 0.0)]])
	_plan.append([31, "_cast", ["you", "w"]])
	_plan.append([50, "_face", ["you", Vector2(1.8, 0.2)]])
	_plan.append([51, "_cast", ["you", "r"]])
	for i in pairs.size():
		_plan.append([56 + i % 4, "_cast", [str(pairs[i][0]), "a"]])
	at = 64 if scene != "teamfight" else int(OS.get_environment("AT")) if OS.has_environment("AT") else 84
	if scene == "feature":
		cam = [Vector3(-16.0, 9.5, 17.0), Vector3(1.0, 0.5, 1.5)]
	elif scene == "fight":
		cam = [Vector3(-9.5, 12.5, 19.5), Vector3(0.3, 0.4, 2.4)]

func _stage_ult() -> void:
	# the Archmage's meteor coming down on three of theirs, close and low (CINE)
	var red := _heroes(1)
	var blue := _heroes(0)
	for u in blue:
		_level(u, 9)
		_tough(u)
		u.bot = false
		u.pos = s().spawn(0)
	for i in red.size():
		var u: Dictionary = red[i]
		_level(u, 9)
		_tough(u, 8.0, 0.7)
		u.bot = i < 3
		_place(u, Vector2(-2.0 + 2.0 * float(i % 3), -6.0 - 1.5 * float(i / 3)) if i < 3 else s().spawn(1), Vector2(0, 8))
	var me: Dictionary = s().by_id["you"]
	_place(me, Vector2(0.0, 4.0), Vector2(0, -6))
	_plan = [[20, "_cast", ["you", "r"]]]
	at = 52
	if cine:
		cam = [Vector3(7.0, 4.2, 6.5), Vector3(-0.5, 1.2, -5.0)]

func _stage_wyrm() -> void:
	# the Grave Wyrm up in its pit, three of ours on it, its soul-fire pouring
	var sm = s().moba
	for c in sm.camps:
		if str(c.kind) == "wyrm" and OS.get_environment("NOWYRM") != "1":
			c.next = s().time
	var blue := _heroes(0)
	for i in blue.size():
		var u: Dictionary = blue[i]
		_level(u, 11)
		_tough(u, 8.0, 0.6 + 0.1 * float(i % 3))
		u.bot = str(u.id) != "you" and i < 3
		if i >= 3 and str(u.id) != "you":
			u.pos = s().spawn(0)
	for u in _heroes(1):
		u.bot = false
		u.pos = s().spawn(1)
	var pit := Vector2(26.0, 3.9)
	var me: Dictionary = s().by_id["you"]
	_place(me, pit + Vector2(-4.5, 4.5), pit)
	var n := 0
	for u in blue:
		if str(u.id) == "you" or n >= 2:
			continue
		_place(u, pit + Vector2(-6.0 + 5.0 * float(n), 6.5 - 1.0 * float(n)), pit)
		n += 1
	_plan = [[60, "_cast", ["you", "r"]], [64, "_wyrm_breath", []]]
	at = 86
	if cine:
		cam = [Vector3(16.0, 10.0, 19.0), Vector3(25.0, 1.5, 4.5)]

func _red_tower(lane: int, tier: int) -> Dictionary:
	for tw in s().moba.towers:
		if int(tw.team) == 1 and int(tw.lane) == lane and int(tw.tier) == tier:
			return tw
	return {}

func _stage_tower() -> void:
	# their middle outer tower half down, a wave of ours under it, two of ours hitting it
	var sm = s().moba
	var tw := _red_tower(1, 1)
	var tp: Vector2 = tw.p
	tw.hp = float(tw.max_hp) * 0.42
	for u in _heroes(1):
		u.bot = false
		u.pos = s().spawn(1)
	var blue := _heroes(0)
	for i in blue.size():
		var u: Dictionary = blue[i]
		_level(u, 8)
		_tough(u)
		u.bot = false
		u.pos = s().spawn(0)
	var me: Dictionary = s().by_id["you"]
	_place(me, tp + Vector2(1.2, 5.6), tp)
	var mate: Dictionary = blue[1] if str(blue[0].id) == "you" else blue[0]
	_place(mate, tp + Vector2(-3.0, 6.8), tp)
	mate.bot = true
	# a wave of ours walking in under it
	sm.wave_at = s().time
	_plan = [[2, "_waves_off", []]]
	for k in [30, 48, 66, 84, 102, 120]:
		_plan.append([k, "_hit", ["you", tp]])
	at = 128

func _stage_king() -> void:
	# their keep open (the middle lane's towers, the gate and both King towers down), four of ours on the King, posed
	var sm = s().moba
	for tw in sm.towers:
		if int(tw.team) == 1 and (int(tw.lane) == 1 or int(tw.tier) == 4):
			tw.hp = 0.0
			tw.dead = true
	for g in s().gates:
		if int(g.team) == 1 and int(g.get("lane", 1)) == 1:
			g.hp = 0.0
	(sm.kings[1] as Dictionary).hp = float((sm.kings[1] as Dictionary).max_hp) * 0.35
	for u in _heroes(1):
		u.bot = false
		u.pos = Vector2(-38.0, -12.0)                    # (out of the way: their fountain is right behind the King)
	var king := Vector2(0.0, -99.0)
	var spots := [Vector2(-2.6, 5.2), Vector2(3.2, 3.8), Vector2(-4.4, 2.6), Vector2(1.0, 3.0)]
	var blue := _heroes(0)
	var n := 1
	_plan = []
	for u in blue:
		_level(u, 10)
		_tough(u)
		u.bot = false
		var at_p: Vector2 = king + (spots[0] if str(u.id) == "you" else (spots[n] if n < spots.size() else Vector2(INF, 0)))
		if str(u.id) != "you" and n >= spots.size():
			u.pos = s().spawn(0)
			continue
		_place(u, at_p, king)
		if str(u.id) != "you":
			n += 1
		for f in [12, 30, 48, 66]:
			_plan.append([f + n * 3, "_hit", [str(u.id), king]])
	_plan.append([40, "_face", ["you", king]])
	_plan.append([41, "_cast", ["you", "q"]])
	_plan.append([60, "_face", ["you", king]])
	_plan.append([61, "_cast", ["you", "w"]])
	at = 76
	if cine:
		cam = [Vector3(9.5, 8.0, -84.0), Vector3(-0.6, 2.4, -99.5)]
