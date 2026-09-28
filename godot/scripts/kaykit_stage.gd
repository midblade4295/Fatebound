extends Node3D
# Real-time KayKit battlefield. Presentation only: it mirrors authoritative state and never changes it.
# Assets: KayKit Medieval Hexagon 1.0, Forest Nature 1.0, Adventurers 2.0, Character Animations 1.1 (CC0, Kay Lousberg).

const HEX := "res://assets/kaykit/hex/"
const FOREST := "res://assets/kaykit/forest/"
const HERO_FILES := ["Knight","Rogue_Hooded","Barbarian","Mage","Ranger"]
# Weapon order matches the v114 WEAPONS table: sword, twin daggers, hand axe, greatsword, great axe, staff, wand, bow, crossbow.
const WEAPONS := [
    {"file":"sword_1handed","r":true,"cls":"1h"},
    {"file":"dagger","r":true,"l":true,"cls":"dual"},
    {"file":"axe_1handed","r":true,"cls":"1h"},
    {"file":"sword_2handed","r":true,"cls":"2h"},
    {"file":"axe_2handed","r":true,"cls":"2h"},
    {"file":"staff","r":true,"cls":"magic"},
    {"file":"wand","r":true,"cls":"magic"},
    {"file":"bow_withString","l":true,"cls":"bow","ry":PI},
    {"file":"crossbow_2handed","r":true,"cls":"xbow","ry":PI},
]
const CLASS_ANIMS := {
    "1h":{"idle":"g/Idle_A","attack":"m/Melee_1H_Attack_Slice_Diagonal","big":"m/Melee_1H_Attack_Jump_Chop"},
    "dual":{"idle":"g/Idle_A","attack":"m/Melee_Dualwield_Attack_Stab","big":"m/Melee_Dualwield_Attack_Chop"},
    "2h":{"idle":"m/Melee_2H_Idle","attack":"m/Melee_2H_Attack_Slice","big":"m/Melee_2H_Attack_Spin"},
    "magic":{"idle":"g/Idle_B","attack":"r/Ranged_Magic_Shoot","big":"r/Ranged_Magic_Summon"},
    "bow":{"idle":"r/Ranged_Bow_Idle","attack":"r/Ranged_Bow_Release","big":"r/Ranged_Bow_Release_Up"},
    "xbow":{"idle":"r/Ranged_2H_Aiming","attack":"r/Ranged_2H_Shoot","big":"r/Ranged_2H_Shooting"},
}
const ACTOR_SCALE := 1.02
const GROUND_TINT := Color(0.66,0.69,0.5)
const HEAD_HEIGHT := 2.75

static var _scene_cache: Dictionary = {}
# Vulkan (Mobile renderer) lights in linear space, so lit surfaces read darker than on
# Compatibility. Compensate the LIGHTS (sun/fill/ambient), not exposure: exposure would also
# brighten the unshaded backdrops, which are already colour-correct via source_color.
# Tuned per mode against Compatibility mean luminance (see commit message).
static var VULKAN_EXPOSURE := 1.0
static var VULKAN_AMBIENT := 9.0
static var VULKAN_LIGHT := 3.75
static var VULKAN_PORTRAIT_EXPOSURE := 1.0
static var VULKAN_PORTRAIT_AMBIENT := 4.0
static var VULKAN_PORTRAIT_LIGHT := 2.5
static var _anim_libs: Dictionary = {}
var _vk_light := 1.0

var camera: Camera3D
var sun: DirectionalLight3D
var reduce_motion := false
var actors: Dictionary = {}
var _terrain: Node3D
var _heights: Dictionary = {}
var _tower_root: Node3D
var _tower_lead := -2
var _tower_index := -1
var _pan := 0.0
var _time := 0.0
var _fx: Array = []
var _clouds: Array[Node3D] = []
var mode := "battle":
    set(value):
        if value == mode:
            return
        mode = value
        _aim_camera()

static func scene(path: String) -> PackedScene:
    if not _scene_cache.has(path):
        _scene_cache[path] = load(path) if ResourceLoader.exists(path) else null
    return _scene_cache[path]

static func anim_libraries() -> Dictionary:
    if _anim_libs.is_empty():
        for spec in [["g","Rig_Medium_General"],["m","Rig_Medium_CombatMelee"],["r","Rig_Medium_CombatRanged"]]:
            var packed := scene("res://assets/kaykit/anim/%s.glb" % spec[1])
            if packed == null:
                continue
            var holder := packed.instantiate()
            var player: AnimationPlayer = holder.find_child("AnimationPlayer",true,false)
            if player != null:
                var lib: AnimationLibrary = player.get_animation_library("")
                for n in lib.get_animation_list():
                    var a: Animation = lib.get_animation(n)
                    if n.contains("Idle") or n.contains("Aiming") or n.ends_with("_Pose"):
                        a.loop_mode = Animation.LOOP_LINEAR
                _anim_libs[spec[0]] = lib
            holder.free()
    return _anim_libs

func _ready() -> void:
    _build_lighting()
    if mode == "portrait":
        _build_pedestal()
        return
    _build_terrain()
    _build_scenery()

func _process(delta: float) -> void:
    _time += delta
    if not reduce_motion:
        for i in _clouds.size():
            var c := _clouds[i]
            c.position.x = fposmod(c.get_meta("x0") + _time*(0.18+0.05*i) + 26.0, 52.0) - 26.0
    for id in actors:
        var a: Dictionary = actors[id]
        var root: Node3D = a.root
        if not is_instance_valid(root):
            continue
        if mode == "portrait":
            root.rotation.y = 0.42 + (0.0 if reduce_motion else sin(_time*0.45)*0.4)
        # Lunge toward the enemy line during an attack, recoil on a hit.
        var off := 0.0
        var at: float = a.get("lunge_at",-10.0)
        var t := _time - at
        if t >= 0.0 and t < 0.6 and not reduce_motion:
            off = sin(t/0.6*PI) * (0.55 if a.get("lunge_big",false) else 0.38)
        var ht := _time - float(a.get("hit_at",-10.0))
        if ht >= 0.0 and ht < 0.35 and not reduce_motion:
            off -= sin(ht/0.35*PI)*0.16
        root.position = a.home + a.face * off
    for i in range(_fx.size()-1,-1,-1):
        var fx: Dictionary = _fx[i]
        var age := _time - float(fx.at)
        var node: Node3D = fx.node
        if age > float(fx.life) or not is_instance_valid(node):
            if is_instance_valid(node):
                node.queue_free()
            _fx.remove_at(i)
            continue
        var u := age/float(fx.life)
        match str(fx.kind):
            "ring":
                node.scale = Vector3.ONE*(0.4+u*float(fx.get("grow",2.2)))
                var m: StandardMaterial3D = fx.mat
                m.albedo_color.a = (1.0-u)*0.85
            "spark":
                node.position = fx.p0 + Vector3(0,u*1.6,0)
                var m2: StandardMaterial3D = fx.mat
                m2.albedo_color.a = 1.0-u

# ---------- lighting and atmosphere ----------
func _build_lighting() -> void:
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("#9fb0b4")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("#c9c7b4")
    var vk := RenderingServer.get_current_rendering_method() != "gl_compatibility"
    var vk_amb: float = (VULKAN_PORTRAIT_AMBIENT if mode == "portrait" else VULKAN_AMBIENT) if vk else 1.0
    var vk_exp: float = (VULKAN_PORTRAIT_EXPOSURE if mode == "portrait" else VULKAN_EXPOSURE) if vk else 1.0
    _vk_light = (VULKAN_PORTRAIT_LIGHT if mode == "portrait" else VULKAN_LIGHT) if vk else 1.0
    env.ambient_light_energy = 0.30 * vk_amb
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    # Vulkan/Mobile lights in linear space and reads darker than Compatibility; compensate.
    env.tonemap_exposure = 0.86 * vk_exp
    env.tonemap_white = 3.0
    env.fog_enabled = true
    env.fog_light_color = Color("#8ea3ad")
    env.fog_mode = Environment.FOG_MODE_DEPTH
    env.fog_depth_begin = 24.0
    env.fog_depth_end = 70.0
    env.fog_density = 0.5
    env.fog_sky_affect = 0.0
    env.glow_enabled = true
    env.glow_intensity = 0.35
    env.glow_bloom = 0.04
    env.adjustment_enabled = true
    env.adjustment_saturation = 1.06
    env.adjustment_contrast = 1.06
    _build_backdrop()
    var we := WorldEnvironment.new()
    we.environment = env
    add_child(we)
    sun = DirectionalLight3D.new()
    sun.light_color = Color("#ffe8c4")
    sun.light_energy = 1.05 * _vk_light
    sun.rotation_degrees = Vector3(-52,-38,0)
    sun.shadow_enabled = true
    sun.shadow_opacity = 0.86
    sun.shadow_blur = 1.4
    sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
    sun.directional_shadow_max_distance = 42.0
    add_child(sun)
    var fill := DirectionalLight3D.new()
    fill.light_color = Color("#9fc2ff")
    fill.light_energy = 0.28 * _vk_light
    fill.rotation_degrees = Vector3(-25,150,0)
    add_child(fill)
    camera = Camera3D.new()
    camera.fov = 46.0
    camera.near = 0.3
    camera.far = 120.0
    add_child(camera)
    _aim_camera()

func _build_backdrop() -> void:
    if mode == "portrait":
        # A dark stage with a soft warm glow behind the hero.
        var ps := Shader.new()
        ps.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
// source_color: authored in sRGB, converted correctly on both Compatibility and Vulkan.
uniform vec4 core : source_color = vec4(0.16, 0.24, 0.27, 1.0);
uniform vec4 edge : source_color = vec4(0.025, 0.05, 0.07, 1.0);
void fragment() {
    vec2 p = UV - vec2(0.5, 0.42);
    float d = length(p * vec2(1.0, 1.35));
    ALBEDO = mix(core.rgb, edge.rgb, smoothstep(0.02, 0.55, d));
}
"""
        var pm := ShaderMaterial.new()
        pm.shader = ps
        var pq := QuadMesh.new()
        pq.size = Vector2(16,12)
        var pc := MeshInstance3D.new()
        pc.mesh = pq
        pc.material_override = pm
        pc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        pc.position = Vector3(0,2.0,-5.0)
        add_child(pc)
        return
    # A painted-sky gradient card far behind the field: cool slate at the top, hazy warm light at the horizon.
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
// source_color: authored in sRGB, converted correctly on both Compatibility and Vulkan.
uniform vec4 top : source_color = vec4(0.30, 0.38, 0.44, 1.0);
uniform vec4 mid : source_color = vec4(0.56, 0.63, 0.66, 1.0);
uniform vec4 low : source_color = vec4(0.80, 0.80, 0.72, 1.0);
void fragment() {
    float y = UV.y;
    vec3 c = mix(top.rgb, mid.rgb, smoothstep(0.0, 0.55, y));
    c = mix(c, low.rgb, smoothstep(0.55, 1.0, y));
    ALBEDO = c;
}
"""
    var mat := ShaderMaterial.new()
    mat.shader = shader
    var quad := QuadMesh.new()
    quad.size = Vector2(140,40)
    var card := MeshInstance3D.new()
    card.mesh = quad
    card.material_override = mat
    card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    card.position = Vector3(0,12,-48)
    add_child(card)

func _aim_camera() -> void:
    if camera == null:
        return
    if mode == "portrait":
        camera.fov = 30.0
        camera.position = Vector3(0, 2.3, 6.2)
        camera.look_at(Vector3(0, 1.05, 0))
    elif mode == "raid":
        camera.position = Vector3(_pan, 9.0, 15.0)
        camera.look_at(Vector3(_pan, 1.6, -2.5))
        _project(46.0)
    else:
        camera.position = Vector3(_pan, 14.2, 16.4)
        camera.look_at(Vector3(_pan, 0.0, -1.3))
        _project(44.0)

# The battlefield can sit under a translucent HUD. The shot is composed for the clear window between
# the HUD bars (vertical fov across that window) and lens-shifted so its centre lands there, while the
# rest of the full-screen render keeps showing the world behind the HUD.
var clear_zone := Rect2()
var render_size := Vector2.ZERO

func set_clear_zone(zone: Rect2, full: Vector2) -> void:
    if zone == clear_zone and full == render_size:
        return
    clear_zone = zone
    render_size = full
    _aim_camera()

func _project(fov: float) -> void:
    if clear_zone.size.y < 8.0 or render_size.y < 8.0:
        camera.projection = Camera3D.PROJECTION_PERSPECTIVE
        camera.keep_aspect = Camera3D.KEEP_HEIGHT
        camera.fov = fov
        return
    var px := 2.0*camera.near*tan(deg_to_rad(fov*0.5))/clear_zone.size.y
    var centre := clear_zone.get_center()
    camera.projection = Camera3D.PROJECTION_FRUSTUM
    camera.keep_aspect = Camera3D.KEEP_HEIGHT
    camera.size = render_size.y*px
    camera.frustum_offset = Vector2((render_size.x*0.5-centre.x)*px,(centre.y-render_size.y*0.5)*px)

func set_pan(value: float) -> void:
    _pan = value
    _aim_camera()

# ---------- terrain ----------
func _hex_pos(col: int, row: int) -> Vector3:
    return Vector3(col*2.0 + (1.0 if row % 2 != 0 else 0.0), 0.0, row*1.732)

func _place(path: String, parent: Node3D, pos: Vector3, rot := 0.0, s := 1.0) -> Node3D:
    var packed := scene(path)
    if packed == null:
        return null
    var node: Node3D = packed.instantiate()
    node.position = pos
    node.rotation.y = rot
    node.scale = Vector3.ONE*s
    parent.add_child(node)
    return node

func _mesh_of(path: String) -> Dictionary:
    var packed := scene(path)
    if packed == null:
        return {}
    var holder := packed.instantiate()
    var mi: MeshInstance3D = holder.find_children("*","MeshInstance3D",true,false)[0]
    var out := {"mesh":mi.mesh,"material":mi.get_active_material(0)}
    holder.free()
    return out

func _build_terrain() -> void:
    # ~360 hex tiles drawn as a few MultiMesh batches (one per tint variant) instead of hundreds of
    # separate draw calls, which matters on mid-range phones running the Compatibility renderer.
    _terrain = Node3D.new()
    add_child(_terrain)
    var rng := RandomNumberGenerator.new()
    rng.seed = 1142
    var groups := {}
    for row in range(-11, 8):
        for col in range(-9, 10):
            var p := _hex_pos(col,row)
            var ax := absf(p.x)
            var h := 0.0
            # Flat arena in the middle, terraced shoulders to the sides and a raised back line.
            if ax > 7.5:
                h = 0.5 + floor(rng.randf()*3.0)*0.25
            elif ax > 5.2:
                h = floor(rng.randf()*3.0)*0.25
            elif p.z < -12.0:
                h = 0.25 + floor(rng.randf()*2.0)*0.25
            elif ax > 4.2 and rng.randf() < 0.35:
                h = 0.25
            p.y = h
            _heights[Vector2i(col,row)] = h
            var variant := rng.randi()%3
            var key := "hex_grass:%d" % variant
            if not groups.has(key):
                groups[key] = []
            groups[key].append(Transform3D(Basis(),p))
            if h >= 0.99:
                if not groups.has("hex_grass_bottom:0"):
                    groups["hex_grass_bottom:0"] = []
                groups["hex_grass_bottom:0"].append(Transform3D(Basis(),Vector3(p.x,h-1.0,p.z)))
    for key in groups:
        var parts: PackedStringArray = key.split(":")
        var src := _mesh_of(HEX+parts[0]+".gltf")
        if src.is_empty():
            continue
        var mm := MultiMesh.new()
        mm.transform_format = MultiMesh.TRANSFORM_3D
        mm.mesh = src.mesh
        mm.instance_count = groups[key].size()
        for i in mm.instance_count:
            mm.set_instance_transform(i,groups[key][i])
        var node := MultiMeshInstance3D.new()
        node.multimesh = mm
        var mat: StandardMaterial3D = (src.material as StandardMaterial3D).duplicate()
        mat.albedo_color = GROUND_TINT*[1.0,0.93,1.05][int(parts[1])]
        mat.albedo_color.a = 1.0
        mat.roughness = 0.95
        node.material_override = mat
        _terrain.add_child(node)

func _tint_ground(root: Node) -> void:
    # KayKit's palette grass reads acid-yellow under filmic light; pull it toward a warm moss green,
    # with three slight value variants so the hex field does not read as one flat sheet.
    var cache := {}
    var rng := RandomNumberGenerator.new()
    rng.seed = 99
    for node in root.find_children("*","MeshInstance3D",true,false):
        var mi := node as MeshInstance3D
        if mi.mesh == null:
            continue
        for surf in mi.mesh.get_surface_count():
            var m := mi.get_active_material(surf)
            if not m is StandardMaterial3D:
                continue
            var variant := rng.randi()%3
            var key := [m,variant]
            if not cache.has(key):
                var t: StandardMaterial3D = m.duplicate()
                t.albedo_color = GROUND_TINT*[1.0,0.93,1.05][variant]
                t.albedo_color.a = 1.0
                t.roughness = 0.95
                cache[key] = t
            mi.set_surface_override_material(surf,cache[key])

func ground(x: float, z: float) -> float:
    var row := int(round(z/1.732))
    var col := int(round((x-(1.0 if row % 2 != 0 else 0.0))/2.0))
    return float(_heights.get(Vector2i(col,row),0.0))

func _prop(path: String, parent: Node3D, x: float, z: float, rot := 0.0, s := 1.0) -> Node3D:
    return _place(path,parent,Vector3(x,ground(x,z),z),rot,s)

func _build_scenery() -> void:
    var props := Node3D.new()
    add_child(props)
    # Rival strongholds flank the field; the contested tower stands on the back wall.
    _prop(HEX+"building_castle_blue.gltf",props,-8.4,-3.6,0.5,1.75)
    _prop(HEX+"building_tower_A_blue.gltf",props,-10.6,0.4,0.0,1.3)
    _prop(HEX+"building_tower_B_blue.gltf",props,-9.6,-8.6,0.0,1.3)
    _prop(HEX+"building_barracks_blue.gltf",props,-11.4,-4.8,0.9,1.2)
    _prop(HEX+"flag_blue.gltf",props,-6.2,-0.8,0.0,1.3)
    _prop(HEX+"building_castle_red.gltf",props,8.4,-3.6,-0.5,1.75)
    _prop(HEX+"building_tower_A_red.gltf",props,10.6,0.4,0.0,1.3)
    _prop(HEX+"building_tower_B_red.gltf",props,9.6,-8.6,0.0,1.3)
    _prop(HEX+"building_barracks_red.gltf",props,11.4,-4.8,-0.9,1.2)
    _prop(HEX+"flag_red.gltf",props,6.2,-0.8,0.0,1.3)
    for i in range(-3,4):
        if i == 0:
            continue
        _prop(HEX+"wall_straight.gltf",props,i*2.0,-12.1,0.0,1.0)
    _prop(HEX+"wall_corner_A_outside.gltf",props,-8.0,-12.1,0.0,1.0)
    _prop(HEX+"wall_corner_A_outside.gltf",props,8.0,-12.1,PI*0.5,1.0)
    _tower_root = Node3D.new()
    _tower_root.position = Vector3(0,ground(0,-12.1),-12.1)
    props.add_child(_tower_root)
    set_tower_lead(-1)
    # Trees, rocks and hills build depth around the arena without crowding the fighting lane.
    var rng := RandomNumberGenerator.new()
    rng.seed = 7
    var trees := ["Tree_1_A_Color1","Tree_1_B_Color1","Tree_2_A_Color1","Tree_2_B_Color1","Tree_3_A_Color1","Tree_3_B_Color1","Tree_4_A_Color1","Tree_4_B_Color1"]
    var spots := [Vector3(-4.8,0,-13.6),Vector3(-1.6,0,-14.2),Vector3(1.9,0,-13.8),Vector3(5.0,0,-14.0),Vector3(-8.6,0,-11.8),Vector3(8.8,0,-12.0),
        Vector3(-7.0,0,-8.0),Vector3(7.2,0,-8.4),Vector3(-6.2,0.25,1.5),Vector3(-7.4,0.5,5.2),Vector3(6.4,0.25,2.4),Vector3(7.6,0.5,6.2),Vector3(-5.2,0,-9.8),Vector3(4.8,0,-10.2),
        Vector3(-3.4,0.25,-14.4),Vector3(3.2,0.25,-14.8),Vector3(-12.5,0.75,-7.5),Vector3(12.6,0.75,-7.0),Vector3(-12.0,0.75,3.0),Vector3(12.2,0.75,1.0),
        Vector3(-6.0,0.5,-15.8),Vector3(6.4,0.5,-16.2),Vector3(0.8,0.5,-16.6),Vector3(-9.2,0.75,8.8),Vector3(9.4,0.75,9.0)]
    for p in spots:
        _prop(FOREST+trees[rng.randi()%trees.size()]+".gltf",props,p.x,p.z,rng.randf()*TAU,0.34+rng.randf()*0.14)
    var bushes := ["Bush_1_A_Color1","Bush_1_B_Color1","Bush_2_A_Color1","Bush_2_B_Color1","Bush_1_C_Color1"]
    for p in [Vector3(-4.6,0,4.0),Vector3(4.8,0,5.5),Vector3(-5.0,0,-2.4),Vector3(5.3,0,-1.6),Vector3(-2.2,0,-7.6),Vector3(2.6,0,-8.4),Vector3(-6.8,0.25,8.2),Vector3(0.4,0,8.8)]:
        _prop(FOREST+bushes[rng.randi()%bushes.size()]+".gltf",props,p.x,p.z,rng.randf()*TAU,0.42+rng.randf()*0.2)
    var rocks := ["Rock_1_A_Color1","Rock_1_B_Color1","Rock_1_C_Color1","Rock_1_D_Color1"]
    for p in [Vector3(-3.4,0,-4.6),Vector3(3.9,0,-5.2),Vector3(-4.2,0,7.4),Vector3(3.2,0,7.9),Vector3(1.6,0,-2.8)]:
        _prop(FOREST+rocks[rng.randi()%rocks.size()]+".gltf",props,p.x,p.z,rng.randf()*TAU,0.5+rng.randf()*0.4)
    for p in [Vector3(-11,0.25,-15),Vector3(11,0.25,-15.5),Vector3(-16,0.5,-12),Vector3(16,0.5,-11)]:
        _prop(HEX+"mountain_A_grass_trees.gltf" if rng.randf()<0.5 else HEX+"mountain_B_grass_trees.gltf",props,p.x,p.z,rng.randf()*TAU,1.3)
    for p in [Vector3(-14.5,0.75,-2),Vector3(14.5,0.75,-3),Vector3(-4.5,0.25,-17.5),Vector3(5,0.25,-18)]:
        _prop(HEX+"hills_A_trees.gltf" if rng.randf()<0.5 else HEX+"hills_B_trees.gltf",props,p.x,p.z,rng.randf()*TAU,1.2)
    for i in 6:
        var cloud := _place(HEX+("cloud_big.gltf" if i%2==0 else "cloud_small.gltf"),props,Vector3(-20+i*8.0,7.5+rng.randf()*2.5,-22-rng.randf()*8),rng.randf()*TAU,2.2)
        if cloud != null:
            cloud.set_meta("x0",cloud.position.x)
            _clouds.append(cloud)

func set_tower_lead(lead: int) -> void:
    if lead == _tower_lead or _tower_root == null:
        return
    _tower_lead = lead
    for c in _tower_root.get_children():
        c.queue_free()
    var colour := "blue" if lead == 0 else ("red" if lead == 1 else "")
    if colour.is_empty():
        _place(HEX+"building_scaffolding.gltf",_tower_root,Vector3.ZERO,0.0,1.6)
        _place(HEX+"wall_straight_gate.gltf",_tower_root,Vector3.ZERO,0.0,1.0)
    else:
        _place(HEX+"building_tower_A_%s.gltf" % colour,_tower_root,Vector3.ZERO,0.0,1.9)
        _place(HEX+"flag_%s.gltf" % colour,_tower_root,Vector3(1.6,0,0.6),0.0,1.1)

func _build_pedestal() -> void:
    # Armory/home portrait: the hero on a small lit hex plinth in a dark vignette.
    for c in get_children():
        if c is WorldEnvironment:
            c.environment.background_color = Color("#07121a")
            c.environment.fog_enabled = false
    var base := Node3D.new()
    add_child(base)
    _place(HEX+"hex_grass.gltf",base,Vector3(0,0,0),0.0,1.0)
    for i in 6:
        var a := PI/6 + i*PI/3
        _place(HEX+"hex_grass.gltf",base,Vector3(cos(a)*2.0,-0.35,sin(a)*2.0),0.0,1.0)
    _tint_ground(base)
    for mi in base.find_children("*","MeshInstance3D",true,false):
        for surf in (mi as MeshInstance3D).mesh.get_surface_count():
            var m := (mi as MeshInstance3D).get_active_material(surf)
            if m is StandardMaterial3D:
                var dim: StandardMaterial3D = m.duplicate()
                dim.albedo_color = GROUND_TINT*0.62
                dim.albedo_color.a = 1.0
                (mi as MeshInstance3D).set_surface_override_material(surf,dim)
    _stage_embers()
    var rim := OmniLight3D.new()
    rim.light_color = Color("#8fd6ff")
    rim.light_energy = 1.1 * _vk_light
    rim.omni_range = 6.0
    rim.position = Vector3(-1.8,2.6,-1.6)
    add_child(rim)
    var warm := OmniLight3D.new()
    warm.light_color = Color("#ffcf8a")
    warm.light_energy = 0.9 * _vk_light
    warm.omni_range = 7.0
    warm.position = Vector3(2.2,2.2,2.4)
    add_child(warm)

func _stage_embers() -> void:
    # Slow warm embers drifting up behind the hero on the armory/home stage.
    if not preload("res://scripts/ui/fx.gd").enabled():
        return
    var quad := QuadMesh.new()
    quad.size = Vector2(0.07,0.07)
    var mat := StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
    mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
    mat.vertex_color_use_as_albedo = true
    mat.albedo_texture = preload("res://scripts/ui/fx.gd").texture("dot")
    quad.material = mat
    var pm := ParticleProcessMaterial.new()
    pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
    pm.emission_box_extents = Vector3(3.2,1.6,0.6)
    pm.direction = Vector3(0.15,1,0)
    pm.spread = 25.0
    pm.gravity = Vector3.ZERO
    pm.initial_velocity_min = 0.12
    pm.initial_velocity_max = 0.35
    pm.scale_min = 0.6
    pm.scale_max = 1.4
    var g := Gradient.new()
    g.offsets = PackedFloat32Array([0.0,0.3,1.0])
    g.colors = PackedColorArray([Color(1,0.7,0.3,0),Color(1,0.62,0.22,0.9),Color(1,0.4,0.1,0)])
    var ramp := GradientTexture1D.new()
    ramp.gradient = g
    pm.color_ramp = ramp
    var p := GPUParticles3D.new()
    p.amount = 16
    p.lifetime = 5.0
    p.preprocess = 4.0
    p.process_material = pm
    p.draw_pass_1 = quad
    p.position = Vector3(0,1.6,-2.2)
    p.visibility_aabb = AABB(Vector3(-5,-3,-2),Vector3(10,7,4))
    add_child(p)

func tower_anchor() -> Vector3:
    return Vector3(0,ground(0,-12.1)+7.4,-12.1)

# ---------- actors ----------
func _make_actor(ci: int, wi: int) -> Dictionary:
    var packed := scene("res://assets/kaykit/heroes/%s.glb" % HERO_FILES[clampi(ci,0,4)])
    if packed == null:
        return {}
    var body: Node3D = packed.instantiate()
    var skeleton: Skeleton3D = body.find_child("Skeleton3D",true,false)
    var w: Dictionary = WEAPONS[clampi(wi,0,WEAPONS.size()-1)]
    if skeleton != null:
        for hand in ["r","l"]:
            if not w.get(hand,false):
                continue
            var slot := BoneAttachment3D.new()
            slot.bone_name = "handslot.%s" % hand
            skeleton.add_child(slot)
            var weapon := scene("res://assets/kaykit/weapons/%s.gltf" % w.file)
            if weapon != null:
                var model: Node3D = weapon.instantiate()
                model.rotation.y = float(w.get("ry",0.0))
                slot.add_child(model)
    var player := AnimationPlayer.new()
    body.add_child(player)
    player.root_node = NodePath("..")
    for key in anim_libraries():
        player.add_animation_library(key,_anim_libs[key])
    for mi in body.find_children("*","MeshInstance3D",true,false):
        (mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    return {"body":body,"player":player,"cls":str(w.cls)}

func sync_actors(entries: Array) -> void:
    # entries: [{id, char, weapon, pos:Vector3, facing:float, dead:bool, big:bool}]
    var keep := {}
    for e in entries:
        var id := str(e.id)
        keep[id] = true
        var a: Dictionary = actors.get(id,{})
        if a.is_empty() or int(a.char) != int(e.char) or int(a.weapon) != int(e.weapon):
            if not a.is_empty() and is_instance_valid(a.root):
                a.root.queue_free()
            var made := _make_actor(int(e.char),int(e.weapon))
            if made.is_empty():
                continue
            var root := Node3D.new()
            add_child(root)
            root.add_child(made.body)
            a = {"root":root,"body":made.body,"player":made.player,"cls":made.cls,"char":int(e.char),"weapon":int(e.weapon),"dead":false,"clip":""}
            actors[id] = a
            _play(a,"idle",true)
        var s := ACTOR_SCALE*(2.3 if e.get("big",false) else 1.0)
        a.root.scale = Vector3.ONE*s
        var home: Vector3 = e.pos
        home.y = ground(home.x,home.z)
        a.home = home
        a.face = Vector3(sin(float(e.facing)),0,0).normalized() if absf(sin(float(e.facing)))>0.01 else Vector3.ZERO
        a.root.rotation.y = float(e.facing)
        a.scale = s
        var dead := bool(e.get("dead",false))
        if dead != bool(a.dead):
            a.dead = dead
            _play(a,"death" if dead else "idle",true)
        a.root.visible = true
    for id in actors.keys():
        if not keep.has(id):
            var a: Dictionary = actors[id]
            if is_instance_valid(a.root):
                a.root.queue_free()
            actors.erase(id)

func _clip(a: Dictionary, kind: String) -> String:
    var set: Dictionary = CLASS_ANIMS.get(a.cls,CLASS_ANIMS["1h"])
    match kind:
        "hit": return "g/Hit_A"
        "death": return "g/Death_A"
        _: return str(set.get(kind,set.idle))

func _play(a: Dictionary, kind: String, force := false) -> void:
    var player: AnimationPlayer = a.player
    if not is_instance_valid(player):
        return
    var clip := _clip(a,kind)
    if not player.has_animation(clip):
        clip = "g/Idle_A"
    if not force and a.clip == clip and player.is_playing():
        return
    a.clip = clip
    player.play(clip,0.12)
    if reduce_motion and kind == "idle":
        player.seek(0.4,true)
        player.pause()
    if kind in ["attack","big","hit"]:
        var back := func():
            if is_instance_valid(player) and a.clip == clip and not a.dead:
                _play(a,"idle",true)
        get_tree().create_timer(minf(player.current_animation_length,1.1)).timeout.connect(back)
    elif kind == "death":
        get_tree().create_timer(maxf(0.1,player.current_animation_length-0.05)).timeout.connect(func():
            if is_instance_valid(player) and a.dead:
                player.play("g/Death_A_Pose"))

func act(id: String, kind: String, big := false) -> void:
    var a: Dictionary = actors.get(id,{})
    if a.is_empty() or a.dead:
        return
    if kind in ["attack","big"]:
        a.lunge_at = _time
        a.lunge_big = big
        _play(a,"big" if big else "attack",true)
    elif kind == "hit":
        a.hit_at = _time
        _play(a,"hit",true)
        spark(a.root.global_position + Vector3(0,1.4*float(a.scale),0),Color("#ffd27a"))

func head_position(id: String) -> Vector3:
    var a: Dictionary = actors.get(id,{})
    if a.is_empty() or not is_instance_valid(a.root):
        return Vector3.ZERO
    return a.root.global_position + Vector3(0,HEAD_HEIGHT*float(a.get("scale",ACTOR_SCALE)),0)

func foot_position(id: String) -> Vector3:
    var a: Dictionary = actors.get(id,{})
    if a.is_empty() or not is_instance_valid(a.root):
        return Vector3.ZERO
    return a.root.global_position

# ---------- effects ----------
func _unshaded(color: Color) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
    m.albedo_color = color
    m.cull_mode = BaseMaterial3D.CULL_DISABLED
    return m

func ring(at: Vector3, color: Color, grow := 2.2, life := 0.8) -> void:
    if reduce_motion:
        return
    var mesh := TorusMesh.new()
    mesh.inner_radius = 0.92
    mesh.outer_radius = 1.0
    mesh.rings = 48
    var node := MeshInstance3D.new()
    node.mesh = mesh
    var m := _unshaded(color)
    node.material_override = m
    node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    node.position = at + Vector3(0,0.08,0)
    add_child(node)
    _fx.append({"kind":"ring","node":node,"mat":m,"at":_time,"life":life,"grow":grow})

func spark(at: Vector3, color: Color) -> void:
    if reduce_motion:
        return
    var mesh := SphereMesh.new()
    mesh.radius = 0.22
    mesh.height = 0.44
    var node := MeshInstance3D.new()
    node.mesh = mesh
    var m := _unshaded(color)
    node.material_override = m
    node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    node.position = at
    add_child(node)
    _fx.append({"kind":"spark","node":node,"mat":m,"at":_time,"life":0.45,"p0":at})
