extends Node3D
# Presentation only: mirrors siege_sim state every frame and never changes it.
const Stage = preload("res://scripts/kaykit_stage.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")

const HEX := "res://assets/kaykit/hex/"
const FOREST := "res://assets/kaykit/forest/"
const GROUND_TINT := Color(0.47, 0.6, 0.38)
const TEAM_COLORS := [Color("#5fd2f0"), Color("#ff7b52")]
const GOLD := Color("#ffd46a")

# Model, weapons (right/left hand) and clips per class. Clip keys: g general, m melee, r ranged,
# mb movement basic, ma movement advanced, t tools.
const LOOKS := {
	"villager": {"model":"Rogue","r":"","l":"","idle":"g/Idle_A","attack":"m/Melee_Unarmed_Attack_Punch_A","ability":"m/Melee_Unarmed_Attack_Kick"},
	"knight": {"model":"Knight","r":"sword_1handed","l":"","idle":"g/Idle_A","attack":"m/Melee_1H_Attack_Slice_Diagonal","ability":"m/Melee_Block_Attack"},
	"barbarian": {"model":"Barbarian","r":"axe_2handed","l":"","idle":"m/Melee_2H_Idle","attack":"m/Melee_2H_Attack_Slice","ability":"m/Melee_2H_Attack_Spin"},
	"rogue": {"model":"Rogue_Hooded","r":"dagger","l":"dagger","idle":"g/Idle_B","attack":"m/Melee_Dualwield_Attack_Stab","ability":"m/Melee_1H_Attack_Jump_Chop"},
	"ranger": {"model":"Ranger","r":"","l":"bow_withString","idle":"r/Ranged_Bow_Idle","attack":"r/Ranged_Bow_Release","ability":"r/Ranged_Bow_Release_Up"},
	"mage": {"model":"Mage","r":"staff","l":"","idle":"g/Idle_B","attack":"r/Ranged_Magic_Shoot","ability":"r/Ranged_Magic_Spellcasting"},
}
const LOOP_HINTS := ["Idle","Running","Walking","Hammering","Holding","Aiming","_Pose","Blocking"]

static var _libs: Dictionary = {}

var sim
var player_id := "you"
var camera: Camera3D
var actors: Dictionary = {}
var oracle_nodes: Array = []
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

# ---------- world ----------
func _build_lighting() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#9fb0b4")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#c9c7b4")
	env.ambient_light_energy = 0.34
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.84
	env.tonemap_white = 3.0
	env.fog_enabled = true
	env.fog_light_color = Color("#8ea3ad")
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 34.0
	env.fog_depth_end = 70.0
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
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.8
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 44.0
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("#9fc2ff")
	fill.light_energy = 0.28
	fill.rotation_degrees = Vector3(-25, 150, 0)
	add_child(fill)
	camera = Camera3D.new()
	camera.fov = 50.0
	camera.near = 0.3
	camera.far = 110.0
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
	for row in range(-21, 22):
		for col in range(-11, 11):
			var p := hex_pos(col, row)
			var ax := absf(p.x)
			var h := 0.0
			var key := "hex_grass:%d" % (rng.randi() % 3)
			if ax > Sim.HALF_W + 1.5:
				h = 0.5 + floor(rng.randf()*3.0)*0.25
			p.y = h
			if not groups.has(key):
				groups[key] = []
			groups[key].append(Transform3D(Basis(), p))
			if h >= 0.99:
				if not groups.has("hex_grass_bottom:0"):
					groups["hex_grass_bottom:0"] = []
				groups["hex_grass_bottom:0"].append(Transform3D(Basis(), Vector3(p.x, h-1.0, p.z)))
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
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
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
	var trees := ["Tree_1_A_Color1","Tree_1_B_Color1","Tree_2_A_Color1","Tree_2_B_Color1","Tree_3_A_Color1"]
	var rocks := ["Rock_1_A_Color1","Rock_1_B_Color1","Rock_1_C_Color1","Rock_1_D_Color1"]
	for ob in sim.obstacles:
		var p := Vector3(ob.p.x, 0, ob.p.y)
		match str(ob.kind):
			"keep":
				var team := 0 if ob.p.y > 0 else 1
				_place(HEX + "building_castle_%s.gltf" % ["blue","red"][team], p, 0.0 if team == 0 else PI, 2.6)
				_place(HEX + "building_barracks_%s.gltf" % ["blue","red"][team], p + Vector3(-6.0 if team == 0 else 6.0, 0, 0), 0.0, 1.5)
			"tower":
				var team2 := 0 if ob.p.y > 0 else 1
				_place(HEX + "building_tower_A_%s.gltf" % ["blue","red"][team2], p, 0.0, 1.5)
			"rock":
				_place(FOREST + rocks[rng.randi() % rocks.size()] + ".gltf", p, rng.randf()*TAU, float(ob.r) * 2.6)
			"tree":
				_place(FOREST + trees[rng.randi() % trees.size()] + ".gltf", p, rng.randf()*TAU, 0.45 + float(ob.r) * 0.12)
			"ruin":
				_place(HEX + "building_scaffolding.gltf", p, 0.4, 1.4)
	for t in 2:
		var th: Vector2 = Sim.throne(t)
		var cl: Vector2 = Sim.cell(t)
		var fg: Vector2 = Sim.forge(t)
		# Throne: where a team brings its rescued Oracle home.
		_place(HEX + "flag_%s.gltf" % ["blue","red"][t], Vector3(th.x - 1.4, 0, th.y), 0.0, 1.4)
		_place(HEX + "flag_%s.gltf" % ["blue","red"][t], Vector3(th.x + 1.4, 0, th.y), 0.0, 1.4)
		_decal(Vector3(th.x, 0.03, th.y), Sim.THRONE_RADIUS, TEAM_COLORS[t], 0.55)
		# Cell: a stone pen inside the enemy keep holding this team's Oracle.
		for i in 5:
			var a := PI*0.15 + i * PI*0.35
			_place(HEX + "fence_stone_straight.gltf", Vector3(cl.x + cos(a)*1.9, 0, cl.y + sin(a)*1.9), -a + PI*0.5, 0.9)
		_decal(Vector3(cl.x, 0.03, cl.y), 1.5, GOLD, 0.35)
		# Forge: tent, crates and a glowing ring where villagers roll for a class.
		_place(HEX + "tent.gltf", Vector3(fg.x + (2.2 if t == 0 else -2.2), 0, fg.y), PI*0.5, 1.2)
		_place(HEX + "barrel.gltf", Vector3(fg.x - 1.6, 0, fg.y + 1.2), 0.0, 1.2)
		_place(HEX + "crate_A_big.gltf", Vector3(fg.x + 1.2, 0, fg.y - 1.6), 0.5, 1.0)
		_place(HEX + "resource_stone.gltf", Vector3(fg.x, 0, fg.y), 0.0, 1.1)
		_decal(Vector3(fg.x, 0.03, fg.y), Sim.FORGE_RADIUS, Color("#ffb24a"), 0.4)
	# Scenery outside the play field.
	for i in 22:
		var side := -1.0 if i % 2 == 0 else 1.0
		var z := -34.0 + i * 3.2
		_place(FOREST + trees[rng.randi() % trees.size()] + ".gltf", Vector3(side * (Sim.HALF_W + 2.5 + rng.randf()*3.0), 0.5, z), rng.randf()*TAU, 0.5 + rng.randf()*0.2)
	for p in [Vector3(-19, 0.5, -20), Vector3(19, 0.5, 18), Vector3(-19, 0.5, 14), Vector3(19, 0.5, -12)]:
		_place(HEX + "mountain_A_grass_trees.gltf", p, rng.randf()*TAU, 1.6)

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
	var tm := TorusMesh.new()
	tm.inner_radius = radius - width
	tm.outer_radius = radius
	tm.rings = 32
	tm.ring_segments = 4
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
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return {"body":body, "player":player}

func _hp_bar() -> MeshInstance3D:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;
uniform float fill = 1.0;
uniform vec4 tint : source_color = vec4(0.4, 0.9, 1.0, 1.0);
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	vec2 uv = UV;
	float border = step(uv.x, 0.03) + step(0.97, uv.x) + step(uv.y, 0.12) + step(0.88, uv.y);
	vec3 col = uv.x < fill ? tint.rgb : vec3(0.08, 0.09, 0.1);
	ALBEDO = mix(col, vec3(0.02), clamp(border, 0.0, 1.0));
	ALPHA = 0.92;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 0.13)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

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
		var bar := _hp_bar()
		bar.position.y = 2.45
		(bar.material_override as ShaderMaterial).set_shader_parameter("tint", TEAM_COLORS[u.team] if u.id != player_id else Color("#7dff8a"))
		root.add_child(bar)
		a = {"root":root, "bar":bar, "ring":ring, "body":null, "player":null, "clip":"", "busy_until":0.0, "dead":false, "last":root.position}
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
	if u.up:
		_glow_body(made.body)
	return a

func _glow_body(body: Node3D) -> void:
	# Upgraded classes get a warm rim of light so a triple roll is readable at a glance.
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D)
		var over := StandardMaterial3D.new()
		over.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		over.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		over.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		over.albedo_color = Color(1.0, 0.75, 0.3, 0.16)
		m.material_overlay = over

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
		var target := Vector3(u.pos.x, 0, u.pos.y)
		var before := root.position
		# Smooth between 30 Hz sim ticks; snap on respawn teleports.
		if before.distance_to(target) > 6.0:
			root.position = target
		else:
			root.position = before.lerp(target, 1.0 - exp(-dt * 22.0))
		var vel := (root.position - before).length() / maxf(dt, 0.001)
		root.rotation.y = lerp_angle(root.rotation.y, float(u.face), 1.0 - exp(-dt * 18.0))
		var bar: MeshInstance3D = a.bar
		bar.visible = u.state != "dead"
		(bar.material_override as ShaderMaterial).set_shader_parameter("fill", clampf(u.hp / maxf(1.0, u.max_hp), 0.0, 1.0))
		(a.ring as MeshInstance3D).visible = u.state != "dead"
		_animate(a, u, vel)
	for id in actors.keys():
		if not seen.has(id):
			actors[id].root.queue_free()
			actors.erase(id)
	_sync_oracles(dt)
	_sync_projectiles()
	_step_fx()
	_update_camera(dt)

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
		for mi in body.find_children("*", "MeshInstance3D", true, false):
			var over := StandardMaterial3D.new()
			over.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			over.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			over.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			over.albedo_color = Color(1.0, 0.8, 0.35, 0.28)
			(mi as MeshInstance3D).material_overlay = over
		player.play("g/Idle_B")
	var halo := MeshInstance3D.new()
	halo.mesh = _ring_mesh(0.42, 0.07)
	halo.material_override = _unshaded(Color(1.0, 0.85, 0.4, 0.95))
	halo.position.y = 2.55
	halo.rotation.x = 0.25
	root.add_child(halo)
	# A tall beam marks a loose or captive Oracle from across the field.
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35
	cyl.bottom_radius = 0.55
	cyl.height = 14.0
	beam.mesh = cyl
	var bc: Color = TEAM_COLORS[team]
	bc.a = 0.16
	beam.material_override = _unshaded(bc)
	beam.position.y = 7.0
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(beam)
	var ground_ring := _decal(Vector3.ZERO, 1.0, TEAM_COLORS[team], 0.8)
	ground_ring.reparent(root, false)
	return {"root":root, "body":body, "player":player, "halo":halo, "beam":beam, "ground":ground_ring, "state":""}

func _sync_oracles(dt: float) -> void:
	for t in 2:
		var n: Dictionary = oracle_nodes[t]
		var o: Dictionary = sim.oracles[t]
		var root: Node3D = n.root
		var target := Vector3(o.pos.x, 0, o.pos.y)
		(n.halo as Node3D).rotation.y += dt * 1.6
		if o.state == "carried":
			var a: Dictionary = actors.get(o.carrier, {})
			if not a.is_empty():
				target = a.root.position + Vector3(0, 1.75, 0)
				root.rotation.y = a.root.rotation.y
			(n.beam as Node3D).visible = false
			(n.ground as Node3D).visible = false
			if n.state != "carried" and n.player != null:
				(n.player as AnimationPlayer).play("t/Holding_B" if (n.player as AnimationPlayer).has_animation("t/Holding_B") else "g/Idle_B")
		else:
			(n.beam as Node3D).visible = true
			(n.ground as Node3D).visible = true
			target.y = 0.0
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
		node.position = Vector3(p.pos.x, 1.2, p.pos.y)
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
func ring_at(at: Vector3, color: Color, grow := 2.2, life := 0.6) -> void:
	if low_fx and life < 0.5:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _ring_mesh(0.5, 0.12)
	var mat := _unshaded(color)
	mi.material_override = mat
	mi.position = at + Vector3(0, 0.08, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_fx.append({"node":mi, "mat":mat, "at":_time, "life":life, "kind":"ring", "grow":grow})

func spark(at: Vector3, color: Color) -> void:
	if low_fx:
		return
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	sm.radial_segments = 6
	sm.rings = 3
	mi.mesh = sm
	var mat := _unshaded(color)
	mi.material_override = mat
	mi.position = at
	add_child(mi)
	var dir := Vector3(randf_range(-1, 1), randf_range(0.6, 1.6), randf_range(-1, 1))
	_fx.append({"node":mi, "mat":mat, "at":_time, "life":0.45, "kind":"spark", "p0":at, "dir":dir})

func number(at: Vector3, text: String, mine: bool) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 64
	l.pixel_size = 0.006
	l.outline_size = 14
	l.modulate = Color("#ff6b5a") if mine else Color("#fff1c2")
	l.position = at
	add_child(l)
	_fx.append({"node":l, "at":_time, "life":0.7, "kind":"number", "p0":at})

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
				var s := 0.4 + u * float(fx.grow)
				node.scale = Vector3(s, 0.3, s)
				(fx.mat as StandardMaterial3D).albedo_color.a = (1.0 - u) * 0.9
			"spark":
				node.position = fx.p0 + fx.dir * u * 1.2
				(fx.mat as StandardMaterial3D).albedo_color.a = 1.0 - u
			"number":
				node.position = fx.p0 + Vector3(0, u * 1.0, 0)
				(node as Label3D).modulate.a = 1.0 - u * u

# ---------- camera ----------
func _update_camera(dt: float) -> void:
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
	camera.position = _cam_target + Vector3(0, 19.0, -ahead * 15.0)
	camera.look_at(_cam_target, Vector3.UP)

func screen_point(world: Vector3) -> Vector2:
	return camera.unproject_position(world)

func is_on_screen(world: Vector3) -> bool:
	return not camera.is_position_behind(world) and Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).has_point(camera.unproject_position(world))
