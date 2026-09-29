# Fatebound castle textures (headless Blender 4.0), Fat Princess-style sandstone:
#   xvfb-run -a blender -b --python godot/tools/blender/castle_art.py
# Env: ONLY=bricks,paving   SIZE (default 1024)   OUTDIR (default assets/castle)
# Each texture is real beveled geometry rendered top-down over exactly one repeat period (with
# overscan), with per-block variation keyed to the block's position in the period -> seamless.
import bpy, os, math, random

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.abspath(os.path.join(HERE, "../.."))
OUTDIR = os.environ.get("OUTDIR", os.path.join(GODOT, "assets/castle"))
ONLY = [x for x in os.environ.get("ONLY", "").split(",") if x]
SIZE = int(os.environ.get("SIZE", "1024"))
os.makedirs(OUTDIR, exist_ok=True)

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE'
    sc.render.resolution_x = SIZE
    sc.render.resolution_y = SIZE
    sc.view_settings.view_transform = 'Standard'
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGB'
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs['Color'].default_value = (0.85, 0.85, 0.9, 1)
    w.node_tree.nodes["Background"].inputs['Strength'].default_value = 0.35
    ee = sc.eevee
    ee.taa_render_samples = 32
    ee.use_gtao = True; ee.gtao_distance = 0.12; ee.gtao_factor = 1.3
    ee.use_overscan = True; ee.overscan_size = 0.25
    ee.use_soft_shadows = True
    sun = bpy.data.lights.new("sun", 'SUN'); sun.energy = 2.2; sun.angle = math.radians(20)
    so = bpy.data.objects.new("sun", sun); sc.collection.objects.link(so)
    so.rotation_euler = (math.radians(35), 0, math.radians(30))
    return sc

def mat(name, c, rough=0.9):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs['Base Color'].default_value = (*c, 1)
    b.inputs['Roughness'].default_value = rough
    return m

def block(x0, y0, w, h, mats, key, gap, bevel, depth=0.12):
    rnd = random.Random(hash(key) & 0xffffffff)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x0 + w / 2, y0 + h / 2, depth / 2))
    o = bpy.context.active_object
    o.scale = (w - gap, h - gap, depth)
    bpy.ops.object.transform_apply(scale=True)
    b = o.modifiers.new("b", 'BEVEL'); b.width = bevel; b.segments = 3
    o.location.z += rnd.uniform(-0.006, 0.006)
    o.rotation_euler.z = rnd.uniform(-0.006, 0.006)
    o.data.materials.append(rnd.choice(mats))

def render(sc, span, name):
    cam = bpy.data.cameras.new("cam"); cam.type = 'ORTHO'; cam.ortho_scale = span
    co = bpy.data.objects.new("cam", cam); sc.collection.objects.link(co)
    co.location = (span / 2, span / 2, 20)
    sc.camera = co
    sc.render.filepath = os.path.join(OUTDIR, name + ".png")
    bpy.ops.render.render(write_still=True)

# Warm sandstone palette (LINEAR colours; ~ sRGB (215,185,135) .. (180,145,100)).
SAND = [(0.68, 0.49, 0.25), (0.62, 0.44, 0.22), (0.72, 0.53, 0.28), (0.57, 0.40, 0.20), (0.66, 0.47, 0.24)]

def bricks():
    """Running-bond wall bricks: 0.5 x 0.25 m, 2 m period (4 bricks x 8 courses)."""
    sc = reset()
    grout = mat("grout", (0.30, 0.21, 0.12), 1.0)
    bpy.ops.mesh.primitive_plane_add(size=8, location=(1, 1, -0.01))
    bpy.context.active_object.data.materials.append(grout)
    mats = [mat("s%d" % i, c) for i, c in enumerate(SAND)]
    W, H, P = 0.5, 0.25, 2.0
    for row in range(-2, 11):
        off = (W / 2) if row % 2 else 0.0
        for col in range(-2, 7):
            x = col * W + off
            y = row * H
            key = (round((x % P) * 100), round((y % P) * 100))
            block(x, y, W, H, mats, key, 0.03, 0.025)
    render(sc, P, "bricks")

def paving():
    """Large flagstones, 2 m period: a 1 m square, two 1 x 0.5 slabs and four 0.5 m squares
    per quadrant arrangement, varied per quadrant (keyed to position -> seamless)."""
    sc = reset()
    grout = mat("grout", (0.28, 0.20, 0.12), 1.0)
    bpy.ops.mesh.primitive_plane_add(size=8, location=(1, 1, -0.01))
    bpy.context.active_object.data.materials.append(grout)
    pale = [(0.78, 0.62, 0.38), (0.72, 0.56, 0.33), (0.82, 0.66, 0.42), (0.70, 0.54, 0.31), (0.75, 0.60, 0.36)]
    mats = [mat("p%d" % i, c, 0.95) for i, c in enumerate(pale)]
    P = 2.0
    layout = [(0.0, 0.0, 1.0, 1.0), (1.0, 0.0, 1.0, 0.5), (1.0, 0.5, 0.5, 0.5), (1.5, 0.5, 0.5, 0.5),
              (0.0, 1.0, 0.5, 1.0), (0.5, 1.0, 0.5, 0.5), (0.5, 1.5, 0.5, 0.5), (1.0, 1.0, 1.0, 1.0)]
    for tx in range(-1, 3):
        for ty in range(-1, 3):
            for (x, y, w, h) in layout:
                gx, gy = tx * P + x, ty * P + y
                key = (round((gx % P) * 100), round((gy % P) * 100))
                block(gx, gy, w, h, mats, key, 0.045, 0.035)
    render(sc, P, "paving")

for name, fn in [("bricks", bricks), ("paving", paving)]:
    if ONLY and name not in ONLY:
        continue
    fn()
    print("CASTLE_ART_DONE", name, flush=True)
