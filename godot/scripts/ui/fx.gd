extends RefCounted
# Cheap GPU particle presets for menus and the battle HUD. Every emitter is capped at a small count,
# uses a tiny generated texture with additive blending, and is skipped entirely when the player turns
# on low-quality effects or reduced motion.
static var low_quality := false
static var reduce_motion := false
static var _tex: Dictionary = {}

static func enabled() -> bool:
    return not low_quality and not reduce_motion

static func texture(kind: String) -> Texture2D:
    if _tex.has(kind):
        return _tex[kind]
    var n := 32
    var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
    for y in n:
        for x in n:
            var p := (Vector2(x, y) + Vector2(0.5, 0.5)) / n * 2.0 - Vector2.ONE
            var a := 0.0
            match kind:
                "dot":
                    a = pow(clampf(1.0 - p.length(), 0, 1), 1.6)
                "streak":
                    a = pow(clampf(1.0 - absf(p.x) * 3.2, 0, 1), 1.4) * pow(clampf(1.0 - absf(p.y), 0, 1), 0.8)
                "star":
                    var cross := maxf(pow(clampf(1.0 - absf(p.x) * 7.0, 0, 1), 2.0) * clampf(1.0 - absf(p.y), 0, 1),
                        pow(clampf(1.0 - absf(p.y) * 7.0, 0, 1), 2.0) * clampf(1.0 - absf(p.x), 0, 1))
                    a = clampf(cross + pow(clampf(1.0 - p.length() * 2.2, 0, 1), 2.0), 0, 1)
            img.set_pixel(x, y, Color(1, 1, 1, a))
    var t := ImageTexture.create_from_image(img)
    _tex[kind] = t
    return t

static func _gradient(colors: Array) -> GradientTexture1D:
    var g := Gradient.new()
    g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
    g.colors = PackedColorArray(colors)
    var t := GradientTexture1D.new()
    t.gradient = g
    return t

static func _node(tex: String, amount: int, lifetime: float) -> GPUParticles2D:
    var node := GPUParticles2D.new()
    node.texture = texture(tex)
    node.amount = amount
    node.lifetime = lifetime
    node.local_coords = true
    var mat := CanvasItemMaterial.new()
    mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
    node.material = mat
    return node

# Ambient emitter filling the box of `parent`, following its size.
static func ambient(parent: Control, kind: String, behind := false) -> GPUParticles2D:
    if not enabled() or parent == null:
        return null
    var pm := ParticleProcessMaterial.new()
    pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
    pm.gravity = Vector3.ZERO
    pm.particle_flag_disable_z = true
    var node: GPUParticles2D
    match kind:
        "embers":
            # Gold/orange sparks rising and drifting sideways.
            node = _node("dot", 18, 3.2)
            pm.direction = Vector3(0.3, -1, 0)
            pm.spread = 35.0
            pm.initial_velocity_min = 8.0
            pm.initial_velocity_max = 26.0
            pm.scale_min = 0.08
            pm.scale_max = 0.22
            pm.color_ramp = _gradient([Color(1, 0.75, 0.3, 0), Color(1, 0.62, 0.2, 0.9), Color(1, 0.35, 0.05, 0)])
        "title":
            # Gold sparks drifting off the title plate.
            node = _node("star", 26, 2.6)
            pm.direction = Vector3(0.4, -1, 0)
            pm.spread = 60.0
            pm.initial_velocity_min = 6.0
            pm.initial_velocity_max = 22.0
            pm.scale_min = 0.12
            pm.scale_max = 0.34
            pm.color_ramp = _gradient([Color(1, 0.85, 0.45, 0), Color(1, 0.8, 0.4, 1), Color(1, 0.5, 0.15, 0)])
        "sparks":
            # Dense orange sparks around the ENTER BATTLE button.
            node = _node("dot", 24, 1.6)
            pm.direction = Vector3(0.6, -1, 0)
            pm.spread = 70.0
            pm.initial_velocity_min = 14.0
            pm.initial_velocity_max = 48.0
            pm.scale_min = 0.08
            pm.scale_max = 0.2
            pm.color_ramp = _gradient([Color(1, 0.8, 0.4, 0), Color(1, 0.65, 0.2, 1), Color(1, 0.3, 0.05, 0)])
        "streaks":
            # Orange light streaks whipping past a call-to-action.
            node = _node("streak", 14, 1.1)
            pm.direction = Vector3(1, -0.35, 0)
            pm.spread = 25.0
            pm.initial_velocity_min = 30.0
            pm.initial_velocity_max = 70.0
            pm.scale_min = 0.25
            pm.scale_max = 0.5
            pm.angle_min = -70.0
            pm.angle_max = -60.0
            pm.color_ramp = _gradient([Color(1, 0.7, 0.3, 0), Color(1, 0.55, 0.15, 0.85), Color(1, 0.3, 0.05, 0)])
        "stars":
            # Blue/cyan twinkles along the XP bar.
            node = _node("star", 14, 1.8)
            pm.direction = Vector3(1, 0, 0)
            pm.spread = 12.0
            pm.initial_velocity_min = 6.0
            pm.initial_velocity_max = 18.0
            pm.scale_min = 0.18
            pm.scale_max = 0.42
            pm.color_ramp = _gradient([Color(0.5, 0.9, 1, 0), Color(0.55, 0.95, 1, 1), Color(0.3, 0.6, 1, 0)])
        "gems":
            node = _node("star", 7, 1.6)
            pm.initial_velocity_min = 0.0
            pm.initial_velocity_max = 4.0
            pm.scale_min = 0.18
            pm.scale_max = 0.34
            pm.color_ramp = _gradient([Color(0.8, 0.5, 1, 0), Color(0.85, 0.55, 1, 1), Color(0.6, 0.3, 1, 0)])
        "gold":
            node = _node("star", 6, 1.6)
            pm.initial_velocity_min = 0.0
            pm.initial_velocity_max = 4.0
            pm.scale_min = 0.16
            pm.scale_max = 0.3
            pm.color_ramp = _gradient([Color(1, 0.85, 0.4, 0), Color(1, 0.85, 0.45, 1), Color(1, 0.6, 0.2, 0)])
        _:
            return null
    node.process_material = pm
    parent.add_child(node)
    if behind:
        parent.move_child(node, 0)
    var fit := func():
        if not is_instance_valid(node):
            return
        node.position = parent.size * 0.5
        pm.emission_box_extents = Vector3(parent.size.x * 0.5, parent.size.y * 0.5, 1)
        node.visibility_rect = Rect2(-parent.size * 0.5 - Vector2(40, 60), parent.size + Vector2(80, 120))
    parent.resized.connect(fit)
    fit.call()
    return node

# One-shot burst at a local position inside `parent`; frees itself when done.
static func burst(parent: CanvasItem, at: Vector2, kind: String) -> void:
    if not enabled() or parent == null:
        return
    var pm := ParticleProcessMaterial.new()
    pm.gravity = Vector3.ZERO
    pm.particle_flag_disable_z = true
    pm.direction = Vector3(0, -1, 0)
    pm.spread = 180.0
    var node: GPUParticles2D
    match kind:
        "roll":
            node = _node("star", 22, 0.6)
            pm.initial_velocity_min = 60.0
            pm.initial_velocity_max = 150.0
            pm.damping_min = 90.0
            pm.damping_max = 140.0
            pm.scale_min = 0.2
            pm.scale_max = 0.45
            pm.color_ramp = _gradient([Color(1, 0.95, 0.7, 1), Color(1, 0.8, 0.35, 1), Color(1, 0.5, 0.1, 0)])
        "crit":
            node = _node("streak", 24, 0.55)
            pm.initial_velocity_min = 90.0
            pm.initial_velocity_max = 190.0
            pm.damping_min = 120.0
            pm.damping_max = 180.0
            pm.scale_min = 0.25
            pm.scale_max = 0.5
            pm.color_ramp = _gradient([Color(1, 1, 0.85, 1), Color(1, 0.55, 0.2, 1), Color(0.9, 0.15, 0.05, 0)])
        "ring":
            # Cyan pulse: particles pushed out on a ring from the die centre.
            node = _node("dot", 20, 0.7)
            pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
            pm.emission_ring_axis = Vector3(0, 0, 1)
            pm.emission_ring_radius = 26.0
            pm.emission_ring_inner_radius = 24.0
            pm.emission_ring_height = 0.0
            pm.radial_velocity_min = 40.0
            pm.radial_velocity_max = 60.0
            pm.initial_velocity_min = 0.0
            pm.initial_velocity_max = 0.0
            pm.scale_min = 0.12
            pm.scale_max = 0.22
            pm.color_ramp = _gradient([Color(0.6, 1, 0.95, 1), Color(0.35, 0.95, 0.9, 0.9), Color(0.2, 0.8, 0.9, 0)])
        _:
            return
    node.process_material = pm
    node.one_shot = true
    node.explosiveness = 0.9
    node.position = at
    parent.add_child(node)
    node.emitting = true
    node.finished.connect(node.queue_free)
