extends Node3D
# Presentation only: mirrors siege_sim state every frame and never changes it.
const Stage = preload("res://scripts/kaykit_stage.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")

const HEX := "res://assets/kaykit/hex/"
const FOREST := "res://assets/kaykit/forest/"
const GROUND_TINT := Color(0.47, 0.6, 0.38)
const TEAM_COLORS := [Color("#5fd2f0"), Color("#ff7b52")]
const GOLD := Color("#ffd46a")
static var VULKAN_EXPOSURE := 1.55
static var VULKAN_AMBIENT := 2.25

# Model, weapons (right/left hand) and clips per class. Clip keys: g general, m melee, r ranged,
# mb movement basic, ma movement advanced, t tools.
const LOOKS := {
	"villager": {"model":"Rogue","r":"","l":"","idle":"g/Idle_A","attack":"m/Melee_Unarmed_Attack_Punch_A","ability":"m/Melee_Unarmed_Attack_Kick"},
	"worker": {"model":"Rogue","r":"axe_1handed","l":"","idle":"g/Idle_A","attack":"m/Melee_1H_Attack_Chop","ability":"m/Melee_1H_Attack_Chop"},
	"knight": {"model":"Knight","r":"sword_1handed","l":"","idle":"g/Idle_A","attack":"m/Melee_1H_Attack_Slice_Diagonal","ability":"m/Melee_Block_Attack"},
	"barbarian": {"model":"Barbarian","r":"axe_2handed","l":"","idle":"m/Melee_2H_Idle","attack":"m/Melee_2H_Attack_Slice","ability":"m/Melee_2H_Attack_Spin"},
	"rogue": {"model":"Rogue_Hooded","r":"dagger","l":"dagger","idle":"g/Idle_B","attack":"m/Melee_Dualwield_Attack_Stab","ability":"m/Melee_1H_Attack_Jump_Chop"},
	"ranger": {"model":"Ranger","r":"","l":"bow_withString","idle":"r/Ranged_Bow_Idle","attack":"r/Ranged_Bow_Release","ability":"r/Ranged_Bow_Release_Up"},
	"mage": {"model":"Mage","r":"staff","l":"","idle":"g/Idle_B","attack":"r/Ranged_Magic_Shoot","ability":"r/Ranged_Magic_Spellcasting"},
}
const LOOP_HINTS := ["Idle","Running","Walking","Hammering","Holding","Aiming","_Pose","Blocking","Chopping","Pickaxing"]

static var _libs: Dictionary = {}
# Shared GPU resources: one mesh/shader per effect type instead of one per hit, so fights don't
# churn buffers or trigger new shader compiles mid-match.
static var _spark_mesh: SphereMesh
static var _rings: Dictionary = {}

var sim
var player_id := "you"
var camera: Camera3D
var actors: Dictionary = {}
var oracle_nodes: Array = []
var gate_nodes: Dictionary = {}
var node_nodes: Dictionary = {}
var stock_piles: Array = []
var catapult_nodes: Array = []
var ladder_nodes: Dictionary = {}
var altar_sacks: Array = []
var proj_nodes: Dictionary = {}
var _fx: Array = []
var _time := 0.0
var _cam_target := Vector3.ZERO
var low_fx := false

static func libraries() -> Dictionary:
	if _libs.is_empty():
		var files := {"g":"General","m":"CombatMelee","r":"CombatRanged","mb":"MovementBasic","ma":"MovementAdvanced","t":"Tools"}
		for key in files:
			var packed := Stage.scene("res://assets/kaykit/anim/Rig_Medium_%s.glb" % files[key])
			if packed == null:
				continue
			var holder := packed.instantiate()
			var player: AnimationPlayer = holder.find_child("AnimationPlayer", true, false)
			if player != null:
				var lib: AnimationLibrary = player.get_animation_library("")
				for n in lib.get_animation_list():
					for hint in LOOP_HINTS:
						if n.contains(hint):
							lib.get_animation(n).loop_mode = Animation.LOOP_LINEAR
							break
				_libs[key] = lib
			holder.free()
	return _libs

func setup(s) -> void:
	sim = s
	_build_lighting()
	_build_terrain()
	_build_props()
	for t in 2:
		oracle_nodes.append(_make_oracle(t))
	_warm_up()

func _warm_up() -> void:
	# Draw one of every effect/projectile type in view during the first frames, so their shader
	# variants compile while the match is loading instead of freezing the first fight.
	var at := Vector3(Sim.spawn(0).x, 0.5, Sim.spawn(0).y)
	ring_at(at, GOLD, 1.0, 0.2)
	spark(at, GOLD)
	number(at, "0", false)
	for kind in ["arrow", "fire"]:
		var n := _make_projectile(kind)
		n.position = at
		get_tree().create_timer(0.3).timeout.connect(n.queue_free)

# ---------- world ----------
func _build_lighting() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#9fb0b4")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#c3c9c4")
	env.ambient_light_energy = 0.5 * (VULKAN_AMBIENT if RenderingServer.get_current_rendering_method() != "gl_compatibility" else 1.0)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Vulkan/Mobile lights in linear space and reads darker than Compatibility with the same
	# settings. Multiplier tuned so Siege's mean brightness matches Compatibility (see commit).
	var vk := RenderingServer.get_current_rendering_method() != "gl_compatibility"
	env.tonemap_exposure = 0.84 * (VULKAN_EXPOSURE if vk else 1.0)
	env.tonemap_white = 3.0
	env.fog_enabled = true
	env.fog_light_color = Color("#8ea3ad")
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 64.0
	env.fog_depth_end = 120.0
	env.fog_density = 0.5
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#ffe8c4")
	sun.light_energy = 1.05
	sun.rotation_degrees = Vector3(-55, -35, 0)
	# No real-time shadows: at this zoom they doubled every triangle for little visual gain.
	# Units are marked by team rings; HP bars are drawn on the 2D HUD.
	sun.shadow_enabled = false
	add_child(sun)
	# Single directional light: the Compatibility renderer can add a per-object pass for each extra
	# directional light, so the old cool fill light is folded into ambient instead.
	camera = Camera3D.new()
	camera.fov = 50.0
	camera.near = 0.3
	camera.far = 190.0
	add_child(camera)

func _mesh_of(path: String) -> Dictionary:
	var packed := Stage.scene(path)
	if packed == null:
		return {}
	var holder := packed.instantiate()
	var found := holder.find_children("*", "MeshInstance3D", true, false)
	var out := {}
	if not found.is_empty():
		var mi: MeshInstance3D = found[0]
		out = {"mesh":mi.mesh, "material":mi.get_active_material(0)}
	holder.free()
	return out

static func hex_pos(col: int, row: int) -> Vector3:
	return Vector3(col*2.0 + (1.0 if row % 2 != 0 else 0.0), 0.0, row*1.732)

func _build_terrain() -> void:
	# One MultiMesh per tile look keeps ~900 hexes to a handful of draw calls on phones.
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var groups := {}
	for row in range(-28, 29):
		for col in range(-16, 16):
			var p := hex_pos(col, row)
			var ax := absf(p.x)
			var h := 0.0
			var band := (row + 28) / 8
			var key := "hex_grass:%d:%d" % [rng.randi() % 3, band]
			if ax > Sim.HALF_W + 1.5:
				h = 0.5 + floor(rng.randf()*3.0)*0.25
			p.y = h
			if not groups.has(key):
				groups[key] = []
			groups[key].append(Transform3D(Basis(), p))
			if h >= 0.99:
				var bkey := "hex_grass_bottom:0:%d" % band
				if not groups.has(bkey):
					groups[bkey] = []
				groups[bkey].append(Transform3D(Basis(), Vector3(p.x, h-1.0, p.z)))
	for key in groups:
		var parts: PackedStringArray = key.split(":")
		var src := _mesh_of(HEX + parts[0] + ".gltf")
		if src.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = src.mesh
		mm.instance_count = groups[key].size()
		for i in mm.instance_count:
			mm.set_instance_transform(i, groups[key][i])
		# Row bands give each batch a tight AABB, so bands off-screen are culled.
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if parts[0].begins_with("hex_grass") and src.material is StandardMaterial3D:
			var mat: StandardMaterial3D = (src.material as StandardMaterial3D).duplicate()
			mat.albedo_color = GROUND_TINT * [1.0, 0.93, 1.05][int(parts[1])]
			mat.albedo_color.a = 1.0
			mat.roughness = 0.95
			node.material_override = mat
		add_child(node)

func _place(path: String, pos: Vector3, rot := 0.0, s := 1.0) -> Node3D:
	var packed := Stage.scene(path)
	if packed == null:
		return null
	var node: Node3D = packed.instantiate()
	node.position = pos
	node.rotation.y = rot
	node.scale = Vector3.ONE * s
	add_child(node)
	return node

func _build_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var forest_trees := ["Tree_1_A_Color1","Tree_1_B_Color1","Tree_2_A_Color1","Tree_2_B_Color1","Tree_3_A_Color1"]
	for t in 2:
		_build_castle(t)
	# Midfield ruin and circular props from the sim.
	for ob in sim.obstacles:
		var p := Vector3(ob.p.x, 0, ob.p.y)
		match str(ob.kind):
			"ruin":
				_place(HEX + "building_scaffolding.gltf", p + Vector3(0, Sim.HILL_H, 0), 0.4, 1.4)
			"forge_building":
				_place(HEX + "building_blacksmith_%s.gltf" % COLOR[ob.team], p, PI * 0.5 if ob.team == 0 else -PI * 0.5, 2.3)
			"workshop_building":
				_place(HEX + "building_market_%s.gltf" % COLOR[ob.team], p, -PI * 0.5 if ob.team == 0 else PI * 0.5, 2.0)
	_build_nodes()
	_build_plateau()
	# Scenery outside the play field.
	for i in 22:
		var side := -1.0 if i % 2 == 0 else 1.0
		var z := -34.0 + i * 3.2
		_place(FOREST + forest_trees[rng.randi() % forest_trees.size()] + ".gltf", Vector3(side * (Sim.HALF_W + 2.5 + rng.randf()*3.0), 0.5, z), rng.randf()*TAU, 0.5 + rng.randf()*0.2)
	for p in [Vector3(-19, 0.5, -20), Vector3(19, 0.5, 18), Vector3(-19, 0.5, 14), Vector3(19, 0.5, -12)]:
		_place(HEX + "mountain_A_grass_trees.gltf", p, rng.randf()*TAU, 1.6)

const COLOR := ["blue", "red"]
static var _floor_mats: Dictionary = {}

func _floor(team: int, x0: float, x1: float, z0: float, z1: float, color: Color, y := 0.03) -> void:
	# Flat floor over the hex terrain for a castle room (coordinates in blue space, mirrored).
	var key := color.to_html()
	if not _floor_mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.95
		_floor_mats[key] = m
	var pm := PlaneMesh.new()
	pm.size = Vector2(absf(x1 - x0), absf(z1 - z0))
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = _floor_mats[key]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var c: Vector2 = Sim._m(team, Vector2((x0 + x1) * 0.5, (z0 + z1) * 0.5))
	mi.position = Vector3(c.x, y, c.y)
	add_child(mi)

static var _block_mats: Dictionary = {}
static var _box: BoxMesh

func _stone(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _block_mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.92
		_block_mats[key] = m
	return _block_mats[key]

func _block(team: int, x0: float, x1: float, z0: float, z1: float, h: float, top: Color) -> void:
	# A raised stone platform (blue-space coords, mirrored for red): stone sides, coloured top.
	if _box == null:
		_box = BoxMesh.new()
		_box.size = Vector3.ONE
	var c: Vector2 = Sim._m(team, Vector2((x0 + x1) * 0.5, (z0 + z1) * 0.5))
	var body := MeshInstance3D.new()
	body.mesh = _box
	body.material_override = _stone(Color("#a09580"))
	body.scale = Vector3(absf(x1 - x0), h, absf(z1 - z0))
	body.position = Vector3(c.x, h * 0.5, c.y)
	add_child(body)
	var pm := PlaneMesh.new()
	pm.size = Vector2(absf(x1 - x0), absf(z1 - z0))
	var lid := MeshInstance3D.new()
	lid.mesh = pm
	lid.material_override = _stone(top)
	lid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lid.position = Vector3(c.x, h + 0.01, c.y)
	add_child(lid)

func _stairs(team: int, x0: float, x1: float, z0: float, z1: float, h: float, steps: int, rising_with_z: bool) -> void:
	# One MultiMesh of box steps per staircase (a single draw call).
	if _box == null:
		_box = BoxMesh.new()
		_box.size = Vector3.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _box
	mm.instance_count = steps
	var depth := (z1 - z0) / float(steps)
	for i in steps:
		var sh := h * float(i + 1) / float(steps)
		var zc := z0 + depth * (float(i) + 0.5) if rising_with_z else z1 - depth * (float(i) + 0.5)
		# Each step is a full-height block from the ground up to its tread.
		var c: Vector2 = Sim._m(team, Vector2((x0 + x1) * 0.5, zc))
		var basis := Basis.from_scale(Vector3(absf(x1 - x0), sh, depth + 0.02))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(c.x, sh * 0.5, c.y)))
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = _stone(Color("#b8ad96"))
	add_child(node)

func _parapet(a: Vector2, b: Vector2) -> void:
	# Low stone parapet along a ledge, standing on its high side (clipped to the field).
	var aa := Vector2(clampf(a.x, -Sim.HALF_W, Sim.HALF_W), a.y)
	var bb := Vector2(clampf(b.x, -Sim.HALF_W, Sim.HALF_W), b.y)
	var length := aa.distance_to(bb)
	if length < 0.3:
		return
	var n := maxi(1, int(round(length / 2.6)))
	var rot := -atan2(bb.y - aa.y, bb.x - aa.x) + PI * 0.5
	var normal := Vector2(-(bb - aa).y, (bb - aa).x).normalized()
	var mid := (aa + bb) * 0.5
	var h := maxf(Sim.height_at(mid + normal * 0.7), Sim.height_at(mid - normal * 0.7))
	for i in n:
		var c := aa.lerp(bb, (float(i) + 0.5) / float(n))
		var piece := length / float(n)
		var s := 2.4
		var off := Vector3(1.0 * s, 0, 0).rotated(Vector3.UP, rot)
		var node := _place(HEX + "fence_stone_straight.gltf", Vector3(c.x, h, c.y) + off, rot, s)
		if node != null:
			node.scale.z = s * piece / (1.15 * s)

func _build_plateau() -> void:
	# Midfield plateau around the ruin with stairs on its north and south faces.
	_block(0, -Sim.HILL_X, Sim.HILL_X, -Sim.HILL_Z, Sim.HILL_Z, Sim.HILL_H, Color("#6f8a52"))
	_stairs(0, -Sim.HILL_STAIR_X, Sim.HILL_STAIR_X, Sim.HILL_Z, Sim.HILL_STAIR_Z, Sim.HILL_H, 6, false)
	_stairs(1, -Sim.HILL_STAIR_X, Sim.HILL_STAIR_X, Sim.HILL_Z, Sim.HILL_STAIR_Z, Sim.HILL_H, 6, false)
	for w in sim.walls:
		if w.team == -1 and w.kind == "ledge":
			_parapet(w.a, w.b)

func _wall_run(a: Vector2, b: Vector2, path: String) -> void:
	# Lay 5.2 m wall models along a segment (clipped to the field), stretched slightly to fit.
	var aa := Vector2(clampf(a.x, -Sim.HALF_W, Sim.HALF_W), clampf(a.y, -Sim.HALF_L, Sim.HALF_L))
	var bb := Vector2(clampf(b.x, -Sim.HALF_W, Sim.HALF_W), clampf(b.y, -Sim.HALF_L, Sim.HALF_L))
	var length := aa.distance_to(bb)
	if length < 0.5:
		return
	var n := maxi(1, int(round(length / Sim.SEG)))
	var piece := length / float(n)
	var rot := -atan2(bb.y - aa.y, bb.x - aa.x)
	for i in n:
		var c := aa.lerp(bb, (float(i) + 0.5) / float(n))
		var node := _place(path, Vector3(c.x, 0, c.y), rot, Sim.WALL_SCALE)
		if node != null:
			node.scale.x = Sim.WALL_SCALE * piece / Sim.SEG

func _build_castle(t: int) -> void:
	var col: String = COLOR[t]
	var face := 0.0 if t == 0 else PI
	# Floors: stone courtyard, dark dungeon, carpeted throne room.
	_floor(t, -13.0, 13.0, Sim.FRONT_Z + 1.0, Sim.INNER_Z, Color("#8f877a"))
	# Raised back rooms: dungeon (west) and throne room (east), each cut by a stair channel.
	for side in [-1.0, 1.0]:
		var top: Color = Color("#57524d") if side < 0.0 else Color("#8a8174")
		var x_in: float = side * Sim.KEEP_X
		var x_out: float = side * 13.0
		var s0: float = side * Sim.STAIR_X0
		var s1: float = side * Sim.STAIR_X1
		_block(t, minf(x_in, x_out), maxf(x_in, x_out), Sim.STAIR_Z1, Sim.HALF_L, Sim.PLAT_H, top)
		_block(t, minf(x_in, s0), maxf(x_in, s0), Sim.INNER_Z, Sim.STAIR_Z1, Sim.PLAT_H, top)
		_block(t, minf(s1, x_out), maxf(s1, x_out), Sim.INNER_Z, Sim.STAIR_Z1, Sim.PLAT_H, top)
		_stairs(t, minf(s0, s1), maxf(s0, s1), Sim.STAIR_Z0, Sim.STAIR_Z1, Sim.PLAT_H, 8, true)
	_floor(t, 7.2, 8.8, Sim.STAIR_Z1 + 0.2, 28.0, Color("#2f5f8a") if t == 0 else Color("#8a3a2f"), Sim.PLAT_H + 0.02)
	# Walls from the sim (so collision and visuals always agree).
	for w in sim.walls:
		if w.team != t:
			continue
		match str(w.kind):
			"wall":
				_wall_run(w.a, w.b, HEX + "wall_straight.gltf")
			"bars":
				_bars(w.a, w.b)
			"ledge":
				_parapet(w.a, w.b)
	# Gates on the front wall; open archways in the inner wall.
	for g in sim.gates:
		if g.team != t:
			continue
		var node := _place(HEX + "wall_straight_gate.gltf", Vector3(g.c.x, 0, g.c.y), face, Sim.WALL_SCALE)
		var doors := []
		for mi in node.find_children("*door*", "MeshInstance3D", true, false):
			doors.append({"node":mi, "sign":1.0 if str(mi.name).contains("left") else -1.0})
		var rubble := Node3D.new()
		rubble.position = Vector3(g.c.x, 0, g.c.y)
		add_child(rubble)
		for i in 3:
			var r := _place(HEX + ["rock_single_D.gltf", "rock_single_E.gltf", "crate_open.gltf"][i],
				Vector3(g.c.x + (i - 1) * 0.9, 0, g.c.y + randf_range(-0.3, 0.3)), randf() * TAU, [3.0, 3.0, 1.6][i])
			if r != null:
				r.reparent(rubble, true)
		rubble.visible = false
		gate_nodes[g.id] = {"doors":doors, "rubble":rubble, "open":0.0, "broken":false}
	# Towers flank both gates; catapult towers on the front corners; the keep at the back.
	for tx in [-7.8, -2.6, 2.6, 7.8]:
		var tp: Vector2 = Sim._m(t, Vector2(tx, Sim.FRONT_Z))
		_place(HEX + "building_tower_A_%s.gltf" % col, Vector3(tp.x, 0, tp.y), face, 1.8)
	for cx in [-12.3, 12.3]:
		var cp: Vector2 = Sim._m(t, Vector2(cx, Sim.FRONT_Z + 0.3))
		var cat := _place(HEX + "building_tower_catapult_%s.gltf" % col, Vector3(cp.x, 0, cp.y), face, 1.9)
		if cat != null:
			var turret: Node3D = cat.find_child("*turret*", true, false)
			var arm: Node3D = cat.find_child("*arm*", true, false)
			catapult_nodes.append({"team":t, "p":cp, "node":cat, "turret":turret, "arm":arm,
				"arm_rest":arm.rotation.x if arm != null else 0.0, "fired":-10.0})
		var bp: Vector2 = Sim._m(t, Vector2(cx, Sim.HALF_L - 0.8))
		_place(HEX + "building_tower_B_%s.gltf" % col, Vector3(bp.x, 0, bp.y), face, 1.7)
	var kp: Vector2 = Sim._m(t, Vector2(0.0, 25.4))
	_place(HEX + "building_castle_%s.gltf" % col, Vector3(kp.x, 0, kp.y), face, 2.6)
	# Throne room: banners either side of the throne, a weapon rack.
	var th: Vector2 = Sim.throne(t)
	for fx in [-1.6, 1.6]:
		var fp: Vector2 = th + Sim._m(t, Vector2(fx, 1.2))
		_place(HEX + "flag_%s.gltf" % col, Vector3(fp.x, Sim.PLAT_H, fp.y), face, 1.6)
	_decal(Vector3(th.x, Sim.PLAT_H + 0.06, th.y), Sim.THRONE_RADIUS, TEAM_COLORS[t], 0.6)
	var wr: Vector2 = Sim._m(t, Vector2(12.0, 23.8))
	_place(HEX + "weaponrack.gltf", Vector3(wr.x, Sim.PLAT_H, wr.y), face + PI * 0.5, 4.0)
	# Dungeon: the cell on the platform, a ladder against the back wall and barrels.
	var cc: Vector2 = Sim._m(t, Sim.CELL_C)
	_decal(Vector3(cc.x, Sim.PLAT_H + 0.06, cc.y), 1.4, GOLD, 0.35)
	var lp: Vector2 = Sim._m(t, Vector2(-12.4, 24.0))
	_place(HEX + "ladder.gltf", Vector3(lp.x, Sim.PLAT_H, lp.y), face + PI * 0.5, 3.4)
	for bx in [Vector2(-12.2, 28.2), Vector2(-4.0, 28.2)]:
		var b2: Vector2 = Sim._m(t, bx)
		_place(HEX + "barrel.gltf", Vector3(b2.x, Sim.PLAT_H, b2.y), randf() * TAU, 2.2)
	# Courtyard: forge ring, workshop ring + stockpiles (piles scale with the team's stock).
	var fg: Vector2 = Sim.forge(t)
	_decal(Vector3(fg.x, 0.06, fg.y), Sim.FORGE_RADIUS, Color("#ffb24a"), 0.45)
	var ws: Vector2 = Sim.workshop(t)
	_decal(Vector3(ws.x, 0.06, ws.y), Sim.WORKSHOP_RADIUS, Color("#9fe07a"), 0.45)
	var piles := {}
	for kind in ["wood", "stone"]:
		var pp: Vector2 = Sim._m(t, Vector2(10.4, 20.0 if kind == "wood" else 16.2))
		var pile := Node3D.new()
		pile.position = Vector3(pp.x, 0, pp.y)
		add_child(pile)
		for i in 6:
			var piece := _place(HEX + ("resource_lumber.gltf" if kind == "wood" else "resource_stone.gltf"),
				Vector3(pp.x + (i % 3 - 1) * 0.75, 0.3 * float(i / 3), pp.y + randf_range(-0.2, 0.2)), randf_range(-0.3, 0.3), 2.2)
			if piece != null:
				piece.reparent(pile, true)
				piece.visible = false
		piles[kind] = pile
	# Fate altar: a stone plinth; a glowing sack sits on it while an offering is ready.
	var ap: Vector2 = Sim.altar(t)
	_place(HEX + "resource_stone.gltf", Vector3(ap.x, 0, ap.y), 0.3, 3.2)
	var sack := _place(HEX + "sack.gltf", Vector3(ap.x, 0.75, ap.y), 0.0, 3.0)
	_decal(Vector3(ap.x, 0.06, ap.y), 1.6, Color("#e6b3ff"), 0.45)
	altar_sacks.append(sack)
	var wb: Vector2 = Sim._m(t, Vector2(7.0, 20.3))
	_place(HEX + "wheelbarrow.gltf", Vector3(wb.x, 0, wb.y), face + 0.8, 3.0)
	stock_piles.append(piles)

func _bars(a: Vector2, b: Vector2) -> void:
	# Cell bars: wooden fence pieces along the segment (the fence model is offset to a hex edge).
	var length := a.distance_to(b)
	var n := maxi(1, int(round(length / 2.3)))
	var rot := -atan2(b.y - a.y, b.x - a.x) + PI * 0.5
	for i in n:
		var c := a.lerp(b, (float(i) + 0.5) / float(n))
		var s := 2.0
		var off := Vector3(1.05 * s, 0, 0).rotated(Vector3.UP, rot)
		_place(HEX + "fence_wood_straight.gltf", Vector3(c.x, Sim.height_at(c), c.y) + off, rot, s)

func _build_nodes() -> void:
	# Trees and quarry stones the workers harvest; a depleted node shows a stump / bare rock.
	for n in sim.nodes:
		var p := Vector3(n.p.x, 0, n.p.y)
		var full: Node3D
		var empty: Node3D
		if n.kind == "wood":
			full = _place(HEX + ("tree_single_A.gltf" if n.id % 2 == 0 else "tree_single_B.gltf"), p, randf() * TAU, 3.2)
			empty = _place(HEX + ("tree_single_A_cut.gltf" if n.id % 2 == 0 else "tree_single_B_cut.gltf"), p, randf() * TAU, 3.2)
		else:
			full = _place(HEX + "resource_stone.gltf", p, randf() * TAU, 4.4)
			empty = _place(HEX + "rock_single_D.gltf", p, randf() * TAU, 3.5)
		if empty != null:
			empty.visible = false
		node_nodes[n.id] = {"full":full, "empty":empty, "state":true}

func _sync_castle(dt: float) -> void:
	for g in sim.gates:
		var gn: Dictionary = gate_nodes.get(g.id, {})
		if gn.is_empty():
			continue
		var broken: bool = not sim.gate_blocks(g)
		if broken != bool(gn.broken):
			gn.broken = broken
			(gn.rubble as Node3D).visible = broken
			for d in gn.doors:
				(d.node as Node3D).visible = not broken
		var want := 1.0 if (g.open and not broken) else 0.0
		gn.open = move_toward(float(gn.open), want, dt * 2.5)
		for d in gn.doors:
			(d.node as Node3D).rotation.y = float(d.sign) * float(gn.open) * PI * 0.5
	for n in sim.nodes:
		var nn: Dictionary = node_nodes.get(n.id, {})
		if nn.is_empty():
			continue
		var has: bool = n.amount > 0
		if has != bool(nn.state):
			nn.state = has
			if nn.full != null:
				(nn.full as Node3D).visible = has
			if nn.empty != null:
				(nn.empty as Node3D).visible = not has
		if has and nn.full != null:
			var k := 0.75 + 0.25 * float(n.amount) / float(n.max)
			(nn.full as Node3D).scale = Vector3.ONE * (3.2 if n.kind == "wood" else 4.4) * k
	for cn in catapult_nodes:
		if cn.arm == null:
			continue
		var age: float = _time - float(cn.fired)
		# Throw: snap forward in 0.15 s, wind back over 0.9 s.
		var swing := 0.0
		if age < 0.15:
			swing = age / 0.15
		elif age < 1.05:
			swing = 1.0 - (age - 0.15) / 0.9
		(cn.arm as Node3D).rotation.x = float(cn.arm_rest) + swing * 1.4
	for t in 2:
		if t < altar_sacks.size() and altar_sacks[t] != null:
			(altar_sacks[t] as Node3D).visible = bool(sim.altars[t].ready)
			if sim.altars[t].ready:
				(altar_sacks[t] as Node3D).rotation.y += dt * 1.2
		var o_node: Dictionary = oracle_nodes[t] if t < oracle_nodes.size() else {}
		if not o_node.is_empty() and o_node.body != null:
			var w := float(sim.oracles[t].get("weight", 0))
			var want := Vector3(1.0 + 0.16 * w, 1.0 + 0.04 * w, 1.0 + 0.16 * w) * 0.95
			var body: Node3D = o_node.body
			body.scale = body.scale.lerp(want, minf(1.0, dt * 3.0))
		for kind in ["wood", "stone"]:
			var pile: Node3D = stock_piles[t][kind]
			var shown := clampi(int(ceil(float(sim.stock[t][kind]) / 5.0)), 0, pile.get_child_count())
			for i in pile.get_child_count():
				(pile.get_child(i) as Node3D).visible = i < shown

func _unshaded(color: Color, additive := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	return m

func _ring_mesh(radius: float, width := 0.14) -> TorusMesh:
	var key := "%.2f:%.2f" % [radius, width]
	if _rings.has(key):
		return _rings[key]
	var tm := TorusMesh.new()
	tm.inner_radius = radius - width
	tm.outer_radius = radius
	tm.rings = 32
	tm.ring_segments = 4
	_rings[key] = tm
	return tm

func _decal(pos: Vector3, radius: float, color: Color, alpha: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _ring_mesh(radius, 0.18)
	mi.scale = Vector3(1, 0.15, 1)
	var c := color
	c.a = alpha
	mi.material_override = _unshaded(c)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	add_child(mi)
	return mi

# ---------- actors ----------
func _make_body(cls: String) -> Dictionary:
	var look: Dictionary = LOOKS.get(cls, LOOKS.villager)
	var packed := Stage.scene("res://assets/kaykit/heroes/%s.glb" % look.model)
	if packed == null:
		return {}
	var body: Node3D = packed.instantiate()
	var skeleton: Skeleton3D = body.find_child("Skeleton3D", true, false)
	if skeleton != null:
		for hand in ["r","l"]:
			var file := str(look.get(hand, ""))
			if file.is_empty():
				continue
			var slot := BoneAttachment3D.new()
			slot.bone_name = "handslot.%s" % hand
			skeleton.add_child(slot)
			var weapon := Stage.scene("res://assets/kaykit/weapons/%s.gltf" % file)
			if weapon != null:
				var model: Node3D = weapon.instantiate()
				if file.begins_with("bow"):
					model.rotation.y = PI
				slot.add_child(model)
	var player := AnimationPlayer.new()
	body.add_child(player)
	player.root_node = NodePath("..")
	for key in libraries():
		player.add_animation_library(key, _libs[key])
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return {"body":body, "player":player}

func _ensure_actor(u: Dictionary) -> Dictionary:
	var a: Dictionary = actors.get(u.id, {})
	var look_key := "%s:%s" % [u.cls, u.up]
	if not a.is_empty() and a.look == look_key:
		return a
	var root: Node3D
	if a.is_empty():
		root = Node3D.new()
		add_child(root)
		root.position = Vector3(u.pos.x, 0, u.pos.y)
		var ring := MeshInstance3D.new()
		ring.mesh = _ring_mesh(0.62 if u.id == player_id else 0.5, 0.12)
		ring.scale = Vector3(1, 0.2, 1)
		var col: Color = GOLD if u.id == player_id else TEAM_COLORS[u.team]
		col.a = 0.9
		ring.material_override = _unshaded(col)
		ring.position.y = 0.05
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ring)
		# HP bars are drawn by the 2D HUD (as in the dice battle); no blob-shadow shader quads.
		a = {"root":root, "ring":ring, "body":null, "player":null, "clip":"", "busy_until":0.0, "dead":false, "last":root.position,
			"team":u.team}
		actors[u.id] = a
	else:
		root = a.root
		if is_instance_valid(a.body):
			a.body.queue_free()
	var made := _make_body(u.cls)
	if made.is_empty():
		return a
	root.add_child(made.body)
	made.body.scale = Vector3.ONE * (1.14 if u.up else 1.0)
	a.body = made.body
	a.player = made.player
	a.look = look_key
	a.cls = u.cls
	a.clip = ""
	a.busy_until = 0.0
	_play(a, str(LOOKS.get(u.cls, LOOKS.villager).idle))
	# Upgraded: bigger body + gold ring (no material overrides on skinned meshes).
	var rc: Color = GOLD if (u.up or u.id == player_id) else TEAM_COLORS[u.team]
	rc.a = 0.9
	(a.ring as MeshInstance3D).material_override = _fx_mat(rc)
	(a.ring as MeshInstance3D).mesh = _ring_mesh(0.75 if u.up else (0.62 if u.id == player_id else 0.5), 0.14 if u.up else 0.12)
	return a

func _play(a: Dictionary, clip: String, speed := 1.0, busy := 0.0) -> void:
	var player: AnimationPlayer = a.player
	if not is_instance_valid(player):
		return
	if not player.has_animation(clip):
		clip = "g/Idle_A"
	if busy > 0.0:
		a.busy_until = _time + busy
	if a.clip == clip and player.is_playing() and busy <= 0.0:
		player.speed_scale = speed
		return
	a.clip = clip
	player.play(clip, 0.1)
	player.speed_scale = speed

func sync(dt: float) -> void:
	_time += dt
	var seen := {}
	for u in sim.units:
		seen[u.id] = true
		var a := _ensure_actor(u)
		if a.is_empty() or not is_instance_valid(a.root):
			continue
		var root: Node3D = a.root
		var target := Vector3(u.pos.x, Sim.height_at(u.pos), u.pos.y)
		var before := root.position
		# Smooth between 30 Hz sim ticks; snap on respawn teleports.
		if before.distance_to(target) > 6.0:
			root.position = target
		else:
			root.position = before.lerp(target, 1.0 - exp(-dt * 22.0))
		var vel := (root.position - before).length() / maxf(dt, 0.001)
		root.rotation.y = lerp_angle(root.rotation.y, float(u.face), 1.0 - exp(-dt * 18.0))
		(a.ring as MeshInstance3D).visible = u.state != "dead"
		_sync_load(a, u)
		_animate(a, u, vel)
	for id in actors.keys():
		if not seen.has(id):
			actors[id].root.queue_free()
			actors.erase(id)
	_sync_oracles(dt)
	_sync_castle(dt)
	_sync_projectiles()
	_step_fx()
	_update_camera(dt)

func _sync_load(a: Dictionary, u: Dictionary) -> void:
	var kind: String = u.load.kind if u.load.n > 0 and u.state != "dead" else ""
	if u.offering and u.state != "dead":
		kind = "offering"
	if kind == str(a.get("load_kind", "")):
		return
	a.load_kind = kind
	if a.has("load_node") and is_instance_valid(a.load_node):
		a.load_node.queue_free()
	if kind == "":
		return
	var packed := Stage.scene(HEX + {"wood":"resource_lumber.gltf", "stone":"resource_stone.gltf", "offering":"sack.gltf"}[kind])
	if packed == null:
		return
	var n: Node3D = packed.instantiate()
	n.scale = Vector3.ONE * 2.2
	n.position = Vector3(0, 2.35, 0)
	(a.root as Node3D).add_child(n)
	a.load_node = n

func _animate(a: Dictionary, u: Dictionary, vel: float) -> void:
	var look: Dictionary = LOOKS.get(u.cls, LOOKS.villager)
	if u.state == "dead":
		if not a.dead:
			a.dead = true
			_play(a, "g/Death_A", 1.0, 99.0)
		return
	if a.dead:
		a.dead = false
		a.busy_until = 0.0
	if _time < float(a.busy_until):
		return
	if u.stun > 0.0:
		_play(a, "g/Hit_B", 0.6)
	elif u.state == "dodge":
		_play(a, "ma/Dodge_Forward", 1.6, 0.3)
	elif u.forge.open:
		_play(a, "t/Hammering")
	elif u.state == "gather":
		var node: Dictionary = sim.nodes[int(u.task.get("node", 0))] if not u.task.is_empty() else {}
		_play(a, "t/Chopping" if node.get("kind", "wood") == "wood" else "t/Pickaxing")
	elif u.state == "repair":
		_play(a, "t/Hammering")
	elif u.carrying:
		_play(a, "mb/Walking_A" if vel > 0.5 else "t/Holding_A", clampf(vel / 2.6, 0.7, 1.6))
	elif vel > 0.6:
		_play(a, "mb/Running_A", clampf(vel / 5.2, 0.7, 1.4))
	else:
		_play(a, str(look.idle))

func on_event(e: Dictionary) -> void:
	var a: Dictionary = actors.get(str(e.get("id", "")), {})
	match str(e.k):
		"attack":
			if a.is_empty():
				return
			var look: Dictionary = LOOKS.get(a.cls, LOOKS.villager)
			var clip := str(look.ability if e.kind == "ability" else look.attack)
			_play(a, clip, 1.7, 0.55)
			if e.ability == "spin":
				ring_at(a.root.position, Color("#ffcf7a"), 2.8, 0.45)
		"hit":
			if a.is_empty():
				return
			spark(a.root.position + Vector3(0, 1.3, 0), Color("#ffd27a"))
			number(a.root.position + Vector3(0, 2.2, 0), str(e.dmg), e.id == player_id)
			if _time >= float(a.busy_until):
				_play(a, "g/Hit_A", 1.4, 0.3)
		"spawn":
			if not a.is_empty():
				a.root.position = Vector3(sim.by_id[e.id].pos.x, 0, sim.by_id[e.id].pos.y)
				ring_at(a.root.position, TEAM_COLORS[sim.by_id[e.id].team], 1.6, 0.6)
		"class":
			if not a.is_empty():
				ring_at(a.root.position, GOLD, 3.0 if e.up else 2.0, 0.8)
				for i in (10 if e.up else 5):
					spark(a.root.position + Vector3(randf_range(-0.6, 0.6), 0.4 + randf()*1.4, randf_range(-0.6, 0.6)), GOLD)
		"nova":
			if not a.is_empty():
				ring_at(a.root.position, Color("#ff8a3a"), 3.3, 0.55)
		"boom":
			ring_at(Vector3(e.pos.x, 0.2, e.pos.y), Color("#ff8a3a"), 1.6, 0.4)
			spark(Vector3(e.pos.x, 0.6, e.pos.y), Color("#ffb04a"))
		"rescue":
			var th: Vector2 = Sim.throne(int(e.team))
			for i in 3:
				ring_at(Vector3(th.x, 0.1, th.y), GOLD, 2.0 + i * 1.5, 0.8 + i * 0.25)
		"gate_hit":
			var g: Dictionary = sim.gates[int(e.gate)]
			var gp: Vector2 = g.c + (Vector2(randf_range(-1.0, 1.0), 0.0))
			spark(Vector3(gp.x, 1.4 + randf() * 1.2, gp.y), Color("#e8d6b0"))
			if randf() < 0.35:
				number(Vector3(g.c.x, 3.2, g.c.y), str(e.dmg), false)
		"gate_broken":
			var g2: Dictionary = sim.gates[int(e.gate)]
			for i in 3:
				ring_at(Vector3(g2.c.x, 0.2, g2.c.y), Color("#e0c9a0"), 2.5 + i, 0.7 + i * 0.2)
			for i in 12:
				spark(Vector3(g2.c.x + randf_range(-2, 2), 0.5 + randf() * 2.5, g2.c.y + randf_range(-1, 1)), Color("#c8b89a"))
		"gate_rebuilt":
			var g3: Dictionary = sim.gates[int(e.gate)]
			ring_at(Vector3(g3.c.x, 0.2, g3.c.y), TEAM_COLORS[int(e.team)], 3.0, 0.8)
		"repair":
			var g4: Dictionary = sim.gates[int(e.gate)]
			if randf() < 0.5:
				spark(Vector3(g4.c.x + randf_range(-1, 1), 1.0 + randf(), g4.c.y), Color("#ffe29a"))
		"gather":
			if not a.is_empty() and randf() < 0.6:
				var nd: Dictionary = sim.nodes[int(e.node)]
				spark(Vector3(nd.p.x, 1.0, nd.p.y), Color("#c9a26b") if e.kind == "wood" else Color("#cfd3d6"))
		"deliver":
			var ws: Vector2 = Sim.workshop(int(e.team))
			ring_at(Vector3(ws.x, 0.1, ws.y), Color("#9fe07a"), 1.4, 0.5)
		"fed":
			var fo: Dictionary = sim.oracles[int(e.team)]
			var fp := Vector3(fo.pos.x, Sim.height_at(fo.pos), fo.pos.y)
			ring_at(fp, Color("#e6b3ff"), 2.4, 0.8)
			for i in 8:
				spark(fp + Vector3(randf_range(-0.8, 0.8), 0.6 + randf() * 1.6, randf_range(-0.8, 0.8)), Color("#f0c8ff"))
		"offering_ready":
			var arp: Vector2 = Sim.altar(int(e.team))
			ring_at(Vector3(arp.x, 0.1, arp.y), Color("#e6b3ff"), 2.0, 0.7)
		"upgrade":
			var ws2: Vector2 = Sim.workshop(int(e.team))
			for i in 2:
				ring_at(Vector3(ws2.x, 0.1, ws2.y), GOLD, 2.5 + i * 1.5, 0.9)
		"catapult_fire":
			var best := {}
			var bd := INF
			for cn in catapult_nodes:
				var d: float = (cn.p as Vector2).distance_to(e.from)
				if int(cn.team) == int(e.team) and d < bd:
					bd = d
					best = cn
			if not best.is_empty():
				best.fired = _time
				if best.turret != null:
					var tgt: Vector2 = e.to
					var cat_node: Node3D = best.node
					var local := cat_node.to_local(Vector3(tgt.x, 0, tgt.y))
					(best.turret as Node3D).rotation.y = atan2(-local.x, -local.z)
			var stone := _place(HEX + "projectile_catapult.gltf", Vector3(e.from.x, 4.2, e.from.y), 0.0, 3.2)
			if stone != null:
				_fx.append({"node":stone, "at":_time, "life":float(e.flight), "kind":"shell",
					"p0":Vector3(e.from.x, 4.2, e.from.y), "p1":Vector3(e.to.x, Sim.height_at(e.to) + 0.3, e.to.y)})
		"catapult_hit":
			var hp := Vector3(e.pos.x, Sim.height_at(e.pos) + 0.15, e.pos.y)
			ring_at(hp, Color("#d9c4a0"), Sim.CATAPULT_AOE * 1.3, 0.55)
			for i in 6:
				spark(hp + Vector3(randf_range(-1, 1), 0.3 + randf(), randf_range(-1, 1)), Color("#bfb3a0"))
		"ladder_up":
			var lp: Vector2 = e.pos
			var own := int(e.team)
			# Leans against the outside face of the enemy wall (the side the builder came from).
			var outward := Vector2(0, 1) if own == 0 else Vector2(0, -1)
			var base: Vector2 = lp + outward * 1.35
			var ln := _place(HEX + "ladder.gltf", Vector3(base.x, 0, base.y), 0.0 if own == 0 else PI, 4.6)
			if ln != null:
				ln.rotation.x = -0.32 if own == 0 else 0.32
				ladder_nodes[int(e.ladder)] = ln
			ring_at(Vector3(base.x, 0.1, base.y), TEAM_COLORS[own], 1.8, 0.6)
		"ladder_hit":
			var lh: Node3D = ladder_nodes.get(int(e.ladder))
			if lh != null:
				spark(lh.position + Vector3(0, 1.2 + randf(), 0), Color("#c9a26b"))
		"ladder_down":
			var ld: Node3D = ladder_nodes.get(int(e.ladder))
			if ld != null:
				for i in 6:
					spark(ld.position + Vector3(randf_range(-0.6, 0.6), 0.4 + randf() * 2.0, randf_range(-0.6, 0.6)), Color("#c9a26b"))
				ld.queue_free()
				ladder_nodes.erase(int(e.ladder))
		"pickup", "drop", "recaptured":
			var o: Dictionary = sim.oracles[int(e.team)]
			ring_at(Vector3(o.pos.x, 0.1, o.pos.y), TEAM_COLORS[int(e.team)], 1.8, 0.6)

# ---------- Oracle ----------
func _make_oracle(team: int) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var made := _make_body("mage")
	var body: Node3D = null
	var player: AnimationPlayer = null
	if not made.is_empty():
		body = made.body
		player = made.player
		# Strip the staff: the Oracle is a captive, not a fighter.
		for slot in body.find_children("*", "BoneAttachment3D", true, false):
			slot.queue_free()
		root.add_child(body)
		body.scale = Vector3.ONE * 0.95
		player.play("g/Idle_B")
	var halo := MeshInstance3D.new()
	halo.mesh = _ring_mesh(0.42, 0.07)
	halo.material_override = _unshaded(Color(1.0, 0.85, 0.4, 0.95))
	halo.position.y = 2.55
	halo.rotation.x = 0.25
	root.add_child(halo)
	var ground_ring := _decal(Vector3.ZERO, 1.0, TEAM_COLORS[team], 0.8)
	ground_ring.reparent(root, false)
	return {"root":root, "body":body, "player":player, "halo":halo, "ground":ground_ring, "state":""}

func _sync_oracles(dt: float) -> void:
	for t in 2:
		var n: Dictionary = oracle_nodes[t]
		var o: Dictionary = sim.oracles[t]
		var root: Node3D = n.root
		var target := Vector3(o.pos.x, Sim.height_at(o.pos), o.pos.y)
		(n.halo as Node3D).rotation.y += dt * 1.6
		if o.state == "carried":
			var a: Dictionary = actors.get(o.carrier, {})
			if not a.is_empty():
				target = a.root.position + Vector3(0, 1.75, 0)
				root.rotation.y = a.root.rotation.y
			(n.ground as Node3D).visible = false
			if n.state != "carried" and n.player != null:
				(n.player as AnimationPlayer).play("t/Holding_B" if (n.player as AnimationPlayer).has_animation("t/Holding_B") else "g/Idle_B")
		else:
			(n.ground as Node3D).visible = true
			target.y = Sim.height_at(o.pos)
			var pulse := 0.8 + sin(_time * 4.0) * 0.2
			(n.ground as Node3D).scale = Vector3(pulse, 0.15, pulse)
			if n.state == "carried" and n.player != null:
				(n.player as AnimationPlayer).play("g/Idle_B")
		n.state = o.state
		root.position = target if root.position.distance_to(target) > 5.0 else root.position.lerp(target, 1.0 - exp(-dt * 20.0))

# ---------- projectiles ----------
func _sync_projectiles() -> void:
	var live := {}
	for p in sim.projectiles:
		live[p.id] = true
		var node: Node3D = proj_nodes.get(p.id)
		if node == null:
			node = _make_projectile(str(p.kind))
			proj_nodes[p.id] = node
		node.position = Vector3(p.pos.x, 1.2 + Sim.height_at(p.pos), p.pos.y)
		node.rotation.y = Sim.angle_of(p.vel)
	for id in proj_nodes.keys():
		if not live.has(id):
			proj_nodes[id].queue_free()
			proj_nodes.erase(id)

func _make_projectile(kind: String) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	if kind == "arrow":
		var packed := Stage.scene("res://assets/kaykit/weapons/arrow_bow.gltf")
		if packed != null:
			var arrow: Node3D = packed.instantiate()
			arrow.rotation.x = PI * 0.5
			arrow.scale = Vector3.ONE * 1.3
			root.add_child(arrow)
			return root
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.28 if kind == "fire" else 0.12
	sm.height = sm.radius * 2.0
	ball.mesh = sm
	ball.material_override = _unshaded(Color(1.0, 0.55, 0.15, 0.95) if kind == "fire" else Color(1, 1, 0.8, 0.9))
	root.add_child(ball)
	return root

# ---------- effects ----------
# No material or text writes per frame here. In Godot's GLES3 renderer every material parameter
# change re-uploads that material's buffer (glBufferData), and changing a Label3D's modulate
# rebuilds its mesh and materials. Field logs showed the Adreno driver hanging after ~5-6k frames
# of that churn, so effects share cached materials and fade by scale only, and damage numbers
# are drawn by the 2D HUD instead of Label3D.
static var _fx_mats: Dictionary = {}
var numbers: Array = []   # [{pos: Vector3, text, mine, at}] read by the HUD

func _fx_mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _fx_mats.has(key):
		_fx_mats[key] = _unshaded(color)
	return _fx_mats[key]

func ring_at(at: Vector3, color: Color, grow := 2.2, life := 0.6) -> void:
	if low_fx and life < 0.5:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _ring_mesh(0.5, 0.12)
	var c := color
	c.a = 0.85
	mi.material_override = _fx_mat(c)
	mi.position = at + Vector3(0, 0.08, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_fx.append({"node":mi, "at":_time, "life":life, "kind":"ring", "grow":grow})

func spark(at: Vector3, color: Color) -> void:
	if low_fx:
		return
	var mi := MeshInstance3D.new()
	if _spark_mesh == null:
		_spark_mesh = SphereMesh.new()
		_spark_mesh.radius = 0.12
		_spark_mesh.height = 0.24
		_spark_mesh.radial_segments = 6
		_spark_mesh.rings = 3
	mi.mesh = _spark_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _fx_mat(color)
	mi.position = at
	add_child(mi)
	var dir := Vector3(randf_range(-1, 1), randf_range(0.6, 1.6), randf_range(-1, 1))
	_fx.append({"node":mi, "at":_time, "life":0.45, "kind":"spark", "p0":at, "dir":dir})

func number(at: Vector3, text: String, mine: bool) -> void:
	numbers.append({"pos":at, "text":text, "mine":mine, "at":_time})
	if numbers.size() > 40:
		numbers.pop_front()

func _step_fx() -> void:
	for i in range(_fx.size()-1, -1, -1):
		var fx: Dictionary = _fx[i]
		var age := _time - float(fx.at)
		var node: Node3D = fx.node
		if age > float(fx.life) or not is_instance_valid(node):
			if is_instance_valid(node):
				node.queue_free()
			_fx.remove_at(i)
			continue
		var u := age / float(fx.life)
		match str(fx.kind):
			"ring":
				# Grow outward and disappear at the end of its life (no alpha fade).
				var s := 0.4 + u * float(fx.grow)
				node.scale = Vector3(s, 0.3, s)
			"shell":
				var p0: Vector3 = fx.p0
				var p1: Vector3 = fx.p1
				node.position = p0.lerp(p1, u) + Vector3(0, 7.0 * u * (1.0 - u), 0)
				node.rotation.x += 0.25
			"spark":
				node.position = fx.p0 + fx.dir * u * 1.2
				node.scale = Vector3.ONE * maxf(0.05, 1.0 - u)
	for i in range(numbers.size()-1, -1, -1):
		if _time - float(numbers[i].at) > 0.8:
			numbers.remove_at(i)

# ---------- camera ----------
var cam_override: Array = []   # [eye: Vector3, target: Vector3] for tests/screenshots only

func _update_camera(dt: float) -> void:
	if cam_override.size() == 2:
		camera.position = cam_override[0]
		camera.look_at(cam_override[1], Vector3.UP)
		return
	var me: Dictionary = sim.by_id.get(player_id, {})
	var focus := Vector3.ZERO
	var a: Dictionary = actors.get(player_id, {})
	if not a.is_empty():
		focus = a.root.position
	if not me.is_empty() and me.state == "dead":
		var sp: Vector2 = Sim.spawn(me.team)
		focus = Vector3(sp.x, 0, sp.y)
	# Look up-field (toward the enemy keep) so more of what's ahead is on screen.
	var ahead := -1.0 if me.get("team", 0) == 0 else 1.0
	var target := focus + Vector3(0, 0, ahead * 3.2)
	_cam_target = target if _cam_target == Vector3.ZERO else _cam_target.lerp(target, 1.0 - exp(-dt * 6.0))
	camera.position = _cam_target + Vector3(0, 38.0, -ahead * 30.0)
	camera.look_at(_cam_target, Vector3.UP)

func bars() -> Array:
	# [{pos, fill, color}] for the HUD to draw 2D health bars over living units.
	var out := []
	for u in sim.units:
		if u.state == "dead":
			continue
		var a: Dictionary = actors.get(u.id, {})
		if a.is_empty() or not is_instance_valid(a.root):
			continue
		var c: Color = Color("#7dff8a") if u.id == player_id else TEAM_COLORS[u.team]
		out.append({"pos": (a.root as Node3D).position + Vector3(0, 2.7, 0), "fill": clampf(u.hp / maxf(1.0, u.max_hp), 0.0, 1.0), "color": c})
	return out

func gate_bars() -> Array:
	# Damaged gates (either team) get a health bar over the arch.
	var out := []
	for g in sim.gates:
		if not sim.gate_blocks(g) or g.hp >= g.max_hp:
			continue
		out.append({"pos": Vector3(g.c.x, 4.2, g.c.y), "fill": g.hp / g.max_hp, "color": TEAM_COLORS[g.team]})
	return out

func screen_point(world: Vector3) -> Vector2:
	return camera.unproject_position(world)

func is_on_screen(world: Vector3) -> bool:
	return not camera.is_position_behind(world) and Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).has_point(camera.unproject_position(world))
