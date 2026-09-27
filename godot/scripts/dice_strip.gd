extends Control
# Three real 3D golden d12 dice. They tumble while a roll is pending and settle on the faces the
# server confirmed; nothing here decides an outcome.
const Wire = preload("res://scripts/arena_wire.gd")
const VisualTheme = preload("res://scripts/ui/visual_theme.gd")
const ATLAS = preload("res://assets/dice/die_faces.png")
const NAMES := {"S":"SWORD","C":"CRITICAL","H":"SHIELD","G":"GOLD","E":"FOCUS","F":"GIFT"}
const SYMBOLS := ["S","C","H","G","E","F"]
const PHI := 1.6180339887
const SPACING := 2.55
var faces: Array = []
var pending := false
var reduce_motion := false
var rolling_until := 0.0
var elapsed := 0.0
var _font: Font
var _viewport: SubViewport
var _camera: Camera3D
var _dice: Array[MeshInstance3D] = []
var _face_frames: Array = []   # [{n,t,b,symbol}]
var _anim: Array = []          # per die: {from:Basis,to:Basis,at:float,spin:Vector3}
var _mesh: ArrayMesh
var _view: TextureRect
var _rot: Array[Basis] = []
var _settled := ["","",""]
var _rolled := false
const DIE_SCALE := 0.5

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    clip_contents = false
    _font = VisualTheme.BOLD_FONT
    _viewport = SubViewport.new()
    _viewport.own_world_3d = true
    _viewport.transparent_bg = true
    _viewport.msaa_3d = Viewport.MSAA_4X
    _viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
    _viewport.size = Vector2i(64,64)
    add_child(_viewport)
    _view = TextureRect.new()
    _view.texture = _viewport.get_texture()
    _view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _view.stretch_mode = TextureRect.STRETCH_SCALE
    _view.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _view.offset_bottom = -16
    add_child(_view)
    var world := Node3D.new()
    _viewport.add_child(world)
    var env := Environment.new()
    env.background_mode = Environment.BG_CLEAR_COLOR
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("#ffe9c0")
    env.ambient_light_energy = 0.55
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.tonemap_exposure = 1.0
    env.tonemap_white = 2.2
    var we := WorldEnvironment.new()
    we.environment = env
    world.add_child(we)
    var key := DirectionalLight3D.new()
    key.light_color = Color("#fff1d2")
    key.light_energy = 1.6
    key.rotation_degrees = Vector3(-38,-32,0)
    world.add_child(key)
    var rim := DirectionalLight3D.new()
    rim.light_color = Color("#9fe6ff")
    rim.light_energy = 0.9
    rim.rotation_degrees = Vector3(-10,150,0)
    world.add_child(rim)
    var under := DirectionalLight3D.new()
    under.light_color = Color("#ffb45a")
    under.light_energy = 0.35
    under.rotation_degrees = Vector3(40,20,0)
    world.add_child(under)
    _camera = Camera3D.new()
    _camera.fov = 26.0
    _camera.position = Vector3(0,0.9,9.5)
    world.add_child(_camera)
    _camera.look_at(Vector3(0,0,0))
    _mesh = _build_d12()
    var mat := StandardMaterial3D.new()
    mat.albedo_texture = ATLAS
    mat.metallic = 0.55
    mat.metallic_specular = 0.7
    mat.roughness = 0.34
    mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
    for i in 3:
        var die := MeshInstance3D.new()
        die.mesh = _mesh
        die.material_override = mat
        die.position = Vector3((i-1)*SPACING,0,0)
        world.add_child(die)
        _dice.append(die)
        _anim.append({"from":Basis(),"to":_target_basis(i,SYMBOLS[(i*2)%6]),"at":-10.0,"spin":Vector3(0.7+i*0.2,1.0,0.3*i).normalized()})
        _rot.append(_anim[i].to)
        die.basis = _anim[i].to.scaled(Vector3.ONE*DIE_SCALE)
    resized.connect(_fit)
    _fit()

func _fit() -> void:
    # Keep the three dice inside the strip on any width: pull the camera back on narrow screens.
    if _camera == null or size.x <= 1:
        return
    var k := clampf(get_viewport().get_final_transform().get_scale().x,1.0,2.0) if get_viewport() != null else 1.0
    _viewport.size = Vector2i((Vector2(size.x,maxf(8.0,size.y-16))*k).round())
    var aspect := size.x/maxf(1.0,size.y-16)
    var need := (SPACING*2+2.0)*0.5
    var half_v := tan(deg_to_rad(_camera.fov*0.5))
    var dist := maxf(need/(half_v*aspect),1.35/half_v)
    _camera.position = Vector3(0,dist*0.095,dist)
    _camera.look_at(Vector3(0,0,0))

func _process(delta: float) -> void:
    elapsed += delta
    if _viewport != null and size.x > 1 and absf(_viewport.size.x - size.x*clampf(get_viewport().get_final_transform().get_scale().x,1.0,2.0)) > 1.5:
        _fit()
    var spinning := (pending or elapsed < rolling_until) and not reduce_motion
    for i in _dice.size():
        var die := _dice[i]
        var a: Dictionary = _anim[i]
        if spinning:
            var axis: Vector3 = a.spin
            _rot[i] = (Basis(axis,delta*(13.0+i*2.2))*_rot[i]).orthonormalized()
            die.basis = _rot[i].scaled(Vector3.ONE*DIE_SCALE)
            die.position.y = absf(sin(elapsed*9.0+i*1.3))*0.35
        else:
            var t := clampf((elapsed-float(a.at))/0.55,0,1)
            if reduce_motion:
                t = 1.0
            var e := 1.0-pow(1.0-t,3.0)
            var q := Quaternion(a.from).slerp(Quaternion(a.to),e)
            _rot[i] = Basis(q)
            die.basis = _rot[i].scaled(Vector3.ONE*DIE_SCALE)
            die.position.y = 0.0 if t >= 1.0 else absf(sin(t*PI*2.0))*0.4*(1.0-t)
    queue_redraw()

func set_faces(value: Variant) -> void:
    if not value is Array or value.size() != 3:
        return
    faces = value.duplicate()
    pending = false
    for i in 3:
        var sym := str(faces[i])
        if not sym in SYMBOLS:
            continue
        # State polls repeat the same faces; only re-aim a die when its face changed or a new roll landed.
        if sym == _settled[i] and not _rolled:
            continue
        _settled[i] = sym
        _anim[i].from = _rot[i]
        _anim[i].to = _target_basis(i,sym)
        _anim[i].at = elapsed
    _rolled = false
    queue_redraw()

func start_roll() -> void:
    pending = true
    _rolled = true
    rolling_until = elapsed+0.5
    for i in 3:
        _anim[i].spin = Vector3(randf_range(-1,1),randf_range(-1,1),randf_range(-1,1)).normalized()

# ---------- geometry ----------
func _build_d12() -> ArrayMesh:
    var verts: Array[Vector3] = []
    for x in [-1,1]:
        for y in [-1,1]:
            for z in [-1,1]:
                verts.append(Vector3(x,y,z))
    for a in [-1,1]:
        for b in [-1,1]:
            verts.append(Vector3(0,a/PHI,b*PHI))
            verts.append(Vector3(a/PHI,b*PHI,0))
            verts.append(Vector3(a*PHI,0,b/PHI))
    var normals: Array[Vector3] = []
    for a in [-1,1]:
        for b in [-1,1]:
            normals.append(Vector3(0,a*PHI,b).normalized())
            normals.append(Vector3(a,0,b*PHI).normalized())
            normals.append(Vector3(a*PHI,b,0).normalized())
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    _face_frames.clear()
    for fi in normals.size():
        var n: Vector3 = normals[fi]
        var best := -INF
        for v in verts:
            best = maxf(best,v.dot(n))
        var ring: Array[Vector3] = []
        for v in verts:
            if absf(v.dot(n)-best) < 0.01:
                ring.append(v)
        var center := Vector3.ZERO
        for v in ring:
            center += v
        center /= ring.size()
        var t := (ring[0]-center).normalized()
        var b := t.cross(n).normalized()
        ring.sort_custom(func(p, q):
            var ap := atan2((p-center).dot(b),(p-center).dot(t))
            var aq := atan2((q-center).dot(b),(q-center).dot(t))
            return ap < aq)
        t = (ring[0]-center).normalized()
        b = t.cross(n).normalized()
        var r := (ring[0]-center).length()
        var sym := fi % 6
        _face_frames.append({"n":n,"t":t,"b":b,"symbol":SYMBOLS[sym]})
        var cell := Vector2((sym%3)/3.0,(sym/3)/2.0)
        var uv := func(p: Vector3) -> Vector2:
            var l := p-center
            return cell+Vector2((0.5+0.42*l.dot(b)/r)/3.0,(0.5-0.42*l.dot(t)/r)/2.0)
        # Keep counter-clockwise winding seen from outside.
        var order := ring.duplicate()
        if (order[1]-order[0]).cross(order[2]-order[0]).dot(n) < 0:
            order.reverse()
        for k in range(1,order.size()-1):
            for p in [order[0],order[k+1],order[k]]:
                st.set_normal(n)
                st.set_uv(uv.call(p))
                st.add_vertex(p)
    return st.commit()

func _target_basis(i: int, sym: String) -> Basis:
    var choices: Array = []
    for f in _face_frames:
        if f.symbol == sym:
            choices.append(f)
    if choices.is_empty():
        return Basis()
    var f: Dictionary = choices[(i+int(elapsed*7.0))%choices.size()]
    var face := Basis(f.b,f.t,f.n)
    var eye := (_camera.position-Vector3((i-1)*SPACING,0,0)).normalized() if _camera != null else Vector3(0,0,1)
    var up := Vector3.UP
    up = (up-eye*up.dot(eye)).normalized()
    # A slight cant keeps the dice from looking pasted flat onto the screen.
    var tilt := Basis(eye,(i-1)*0.12)
    up = tilt*up
    var right := up.cross(eye).normalized()
    var target := Basis(right,up,eye)
    return (target*face.transposed()).orthonormalized()

# ---------- 2D dressing: winner glow and labels ----------
func _die_screen(i: int) -> Vector2:
    if _camera == null or _viewport == null or _viewport.size.x <= 0:
        return Vector2(size.x*(i+0.5)/3,size.y*0.45)
    var p := _camera.unproject_position(_dice[i].global_position)
    return p*Vector2(size.x,size.y-16)/Vector2(_viewport.size)

func _draw() -> void:
    if _font == null or size.x <= 1:
        return
    var match_info: Dictionary = Wire.winning_dice(faces)
    var spinning := (pending or elapsed < rolling_until) and not reduce_motion
    for i in 3:
        var center := _die_screen(i)
        var r := minf(size.y*0.40,size.x*0.13)
        # Contact shadow under each die.
        draw_set_transform(center+Vector2(0,r*0.82),0.0,Vector2(1,0.26))
        draw_circle(Vector2.ZERO,r*0.8,Color(0,0,0,0.32))
        draw_set_transform(Vector2.ZERO)
        var winner: bool = not spinning and (match_info.get("indices",[]) as Array).has(i)
        if winner:
            var pulse := 0.5+0.5*sin(elapsed*5.0)
            draw_circle(center,r*1.02,Color(0.3,0.95,0.92,0.10+0.06*pulse))
            draw_arc(center,r*1.02,0,TAU,64,Color(0.55,1.0,0.95,0.85),3.0,true)
            draw_arc(center,r*1.14,0,TAU,64,Color(0.55,1.0,0.95,0.25+0.2*pulse),2.0,true)
        var symbol: String = str(faces[i]) if faces.size() == 3 else ""
        var label: String = "" if spinning else NAMES.get(symbol,"READY")
        if winner and str(match_info.tier) != "none":
            label = str(match_info.tier).to_upper()+" · "+label
        if not label.is_empty():
            var pos := Vector2(size.x*i/3.0,size.y-3)
            draw_string(_font,pos+Vector2(0,1),label,HORIZONTAL_ALIGNMENT_CENTER,size.x/3.0,11,Color(0,0,0,0.6))
            draw_string(_font,pos,label,HORIZONTAL_ALIGNMENT_CENTER,size.x/3.0,11,Color("#aefcf2") if winner else Color("#f6dc9c"))
