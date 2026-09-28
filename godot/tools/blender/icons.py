# Renders shop/locker/pass icons: weapon + off-hand gear from the KayKit models, and procedural
# gold coins and cut gems (the kit has none). Transparent PNGs; Godot adds the rarity frames.
#   xvfb-run -a blender -b --python godot/tools/blender/icons.py
# Env: OUTDIR (default assets/ui), ONLY (comma list of icon names), SIZE, SAMPLES
import bpy, os, re, math, random
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.abspath(os.path.join(HERE, "../.."))
KAY = os.path.join(GODOT, "assets/kaykit")
OUTDIR = os.environ.get("OUTDIR", os.path.join(GODOT, "assets/ui"))
ONLY = [x for x in os.environ.get("ONLY", "").split(",") if x]
SIZE = int(os.environ.get("SIZE", "320"))
SAMPLES = int(os.environ.get("SAMPLES", "32"))

def catalog_weapons():
    src = open(os.path.join(GODOT, "scripts/meta/economy.gd")).read()
    out = {}
    for m in re.finditer(r'"(\w+)":\s*\{"kind":"weapon".*?"r":"(\w*)", "l":"(\w*)"', src):
        out[m.group(1)] = (m.group(2), m.group(3))
    return out

DEFAULTS = {"default_knight": ("sword_1handed", ""), "default_barbarian": ("axe_2handed", ""),
            "default_rogue": ("dagger", "dagger"), "default_ranger": ("", "bow_withString"),
            "default_mage": ("staff", ""), "default_worker": ("axe_1handed", "")}

# ---------------- scene ----------------
def setup(ortho):
    global _gold, _gold2
    _gold = _gold2 = None          # materials die with the scene reset below
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE'
    ee = sc.eevee
    ee.taa_render_samples = SAMPLES
    ee.use_gtao = True
    ee.gtao_distance = 0.5
    ee.use_soft_shadows = True
    ee.use_bloom = False
    sc.render.resolution_x = SIZE
    sc.render.resolution_y = SIZE
    sc.render.film_transparent = True
    sc.view_settings.view_transform = 'Standard'
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    bgn = w.node_tree.nodes["Background"]
    bgn.inputs['Color'].default_value = (0.62, 0.66, 0.78, 1)
    bgn.inputs['Strength'].default_value = 0.55
    def sun(name, frm, energy, color):
        L = bpy.data.lights.new(name, 'SUN')
        L.energy = energy
        L.color = color
        L.angle = math.radians(12)
        o = bpy.data.objects.new(name, L)
        sc.collection.objects.link(o)
        o.rotation_euler = (Vector((0, 0, 0)) - Vector(frm)).normalized().to_track_quat('-Z', 'Y').to_euler()
    sun("key", (-3.0, -6.0, 5.0), 3.0, (1.0, 0.94, 0.84))
    sun("fill", (5.0, -4.0, 1.0), 0.9, (0.7, 0.8, 1.0))
    sun("rim", (3.0, 6.0, 3.5), 2.4, (0.85, 0.72, 1.0))
    cam = bpy.data.cameras.new("cam")
    cam.type = 'ORTHO'
    cam.ortho_scale = ortho
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    co.location = (0, -12, 0)
    co.rotation_euler = (math.radians(90), 0, 0)
    sc.camera = co
    return sc

def import_model(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    root = bpy.data.objects.new("m", None)
    bpy.context.scene.collection.objects.link(root)
    for o in new:
        if o.parent is None:
            o.parent = root
    bpy.context.view_layer.update()
    return root, new

def bounds(objs):
    pts = [o.matrix_world @ Vector(c) for o in objs if o.type == 'MESH' for c in o.bound_box]
    lo = Vector((min(p[i] for p in pts) for i in range(3)))
    hi = Vector((max(p[i] for p in pts) for i in range(3)))
    return lo, hi

def prep_item(name, longest, roll_deg=None):
    """Import a KayKit weapon model, stand its long axis up with the tip at the top and its
    broad face toward the camera, scale so the long side = `longest`, centre it at the origin."""
    root, objs = import_model(os.path.join(KAY, "weapons", name + ".gltf"))
    lo, hi = bounds(objs)
    ext = hi - lo
    c, b, a = sorted(range(3), key=lambda i: ext[i])          # shortest, middle, longest
    basis = [Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))]
    ea, eb, ec = basis[a], basis[b], basis[c]
    elongated = ext[b] < 0.62 * ext[a]
    if elongated and abs(lo[a]) > abs(hi[a]):
        ea = -ea                                               # the grip is at the model origin
    R = Matrix((eb, -ec, ea))
    if R.determinant() < 0:
        R = Matrix((-eb, -ec, ea))
    roll = (38.0 if elongated else 0.0) if roll_deg is None else roll_deg
    M = Matrix.Rotation(math.radians(roll), 4, 'Y') @ R.to_4x4() @ Matrix.Scale(longest / ext[a], 4)
    root.matrix_basis = M
    bpy.context.view_layer.update()
    lo, hi = bounds(objs)
    root.location = -((lo + hi) * 0.5)
    bpy.context.view_layer.update()
    return root, objs

def render(path):
    sc = bpy.context.scene
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)

# ---------------- gear icons ----------------
def gear_icon(name, r, l):
    setup(4.0 if (r and l) else 3.2)
    if r and l:
        a, _ = prep_item(r, 2.6)
        a.location += Vector((0.5, 0.0, 0.3))
        b, _ = prep_item(l, 1.6, roll_deg=(-22.0 if l in ("crossbow_1handed", "spellbook_open", "smokebomb", "mug_full") else 0.0))
        b.location += Vector((-0.75, -1.4, -0.8))
    else:
        prep_item(r or l, 3.0)
    render(os.path.join(OUTDIR, "icons", name + ".png"))

# ---------------- currency ----------------
def mat(color, metal=0.0, rough=0.5, emit=None, es=0.0):
    m = bpy.data.materials.new("m")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs['Base Color'].default_value = (*color, 1)
    b.inputs['Metallic'].default_value = metal
    b.inputs['Roughness'].default_value = rough
    if emit:
        b.inputs['Emission Color'].default_value = (*emit, 1)
        b.inputs['Emission Strength'].default_value = es
    return m

_gold = _gold2 = None
def make_coin(parent, loc, rot, r=0.5):
    global _gold, _gold2
    if _gold is None:
        _gold = mat((1.0, 0.72, 0.16), 1.0, 0.36)
        _gold2 = mat((1.0, 0.80, 0.26), 1.0, 0.42)
    e = bpy.data.objects.new("c", None)
    bpy.context.scene.collection.objects.link(e)
    e.parent = parent
    e.location = loc
    e.rotation_euler = rot
    bpy.ops.mesh.primitive_cylinder_add(vertices=40, radius=r, depth=r * 0.22)
    rim = bpy.context.active_object
    bev = rim.modifiers.new("b", 'BEVEL'); bev.width = r * 0.05; bev.segments = 2
    bpy.ops.object.shade_smooth()
    rim.data.materials.append(_gold)
    rim.parent = e
    bpy.ops.mesh.primitive_cylinder_add(vertices=40, radius=r * 0.72, depth=r * 0.10, location=(0, 0, r * 0.14))
    boss = bpy.context.active_object
    bpy.ops.object.shade_smooth()
    boss.data.materials.append(_gold2)
    boss.parent = e
    return e

def coin_pile(name, n, radius, height, seed, tilt=55.0, ortho=3.0):
    setup(ortho)
    rnd = random.Random(seed)
    holder = bpy.data.objects.new("pile", None)
    bpy.context.scene.collection.objects.link(holder)
    pts = []
    for i in range(n):
        rr = radius * math.sqrt((i + 0.5) / n) if n > 1 else 0.0
        th = i * 2.39996 + rnd.uniform(-0.2, 0.2)
        h = height * (1.0 - (rr / radius) ** 2) if n > 1 else 0.0
        pts.append((rr, th, h))
    pts.sort(key=lambda p: p[2])
    for rr, th, h in pts:
        slope = (rr / max(radius, 0.01)) * 0.55
        rot = (slope * math.sin(th) * -1 + rnd.uniform(-0.28, 0.28), slope * math.cos(th) + rnd.uniform(-0.28, 0.28), rnd.uniform(0, 6.28))
        make_coin(holder, (rr * math.cos(th), rr * math.sin(th), h + 0.06), rot)
    holder.rotation_euler = (math.radians(tilt), 0, math.radians(-8))
    bpy.context.view_layer.update()
    objs = [o for o in bpy.data.objects if o.type == 'MESH']
    lo, hi = bounds(objs)
    holder.location = -((lo + hi) * 0.5)
    render(os.path.join(OUTDIR, "currency", name + ".png"))

def make_gem(loc, rot, r, color, name="g"):
    m = mat(color, 0.0, 0.04, emit=color, es=0.3)
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    e.location = loc
    e.rotation_euler = rot
    bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=r, radius2=0.0, depth=r * 1.05, location=(0, 0, -r * 0.5))
    pav = bpy.context.active_object
    pav.rotation_euler = (math.pi, 0, 0)
    bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=r, radius2=r * 0.6, depth=r * 0.45, location=(0, 0, r * 0.22))
    crown = bpy.context.active_object
    for o in (pav, crown):
        o.data.materials.append(m)
        o.parent = e
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.shade_flat()
    return e

def gem_icon(name, count):
    setup(2.5 if count == 1 else 3.5)
    layout = [((0, 0, 0), 0.85, (0.05, 0.50, 1.0))]
    if count > 1:
        layout = [((0, 0.1, 0.2), 0.85, (0.05, 0.50, 1.0)), ((-0.95, 0.5, -0.5), 0.55, (0.22, 0.38, 0.95)), ((0.9, 0.3, -0.55), 0.6, (0.02, 0.72, 0.88))]
    for i, (loc, r, col) in enumerate(layout):
        make_gem(loc, (math.radians(-62 + 6 * i), math.radians(8 * i - 8), math.radians(15 + 40 * i)), r, col)
    bpy.context.view_layer.update()
    objs = [o for o in bpy.data.objects if o.type == 'MESH']
    lo, hi = bounds(objs)
    shift = -((lo + hi) * 0.5)
    for o in bpy.data.objects:
        if o.type == 'EMPTY' and o.parent is None and o.name.startswith("g"):
            o.location += shift
    render(os.path.join(OUTDIR, "currency", name + ".png"))

# ---------------- run ----------------
os.makedirs(os.path.join(OUTDIR, "icons"), exist_ok=True)
os.makedirs(os.path.join(OUTDIR, "currency"), exist_ok=True)
tasks = []
for k, (r, l) in {**catalog_weapons(), **DEFAULTS}.items():
    tasks.append((k, lambda k=k, r=r, l=l: gear_icon(k, r, l)))
tasks += [("coin", lambda: coin_pile("coin", 1, 0.0, 0.0, 1, tilt=62.0, ortho=1.5)),
          ("coins_s", lambda: coin_pile("coins_s", 7, 0.75, 0.25, 2, ortho=2.6)),
          ("coins_m", lambda: coin_pile("coins_m", 22, 1.25, 0.6, 3, ortho=3.4)),
          ("coins_l", lambda: coin_pile("coins_l", 60, 1.9, 1.1, 4, ortho=4.6)),
          ("gem", lambda: gem_icon("gem", 1)), ("gems", lambda: gem_icon("gems", 3))]
for name, fn in tasks:
    if ONLY and name not in ONLY:
        continue
    fn()
    print("ICON_DONE", name, flush=True)
