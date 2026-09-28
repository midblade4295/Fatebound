# Renders the home-screen hero backdrop (golden-hour castle) from the KayKit models.
#   xvfb-run -a blender -b --python godot/tools/blender/backdrop.py
# Env: OUT (png path), RESX, RESY, SAMPLES, SUNROT (degrees, sky azimuth; only affects the sky glow)
import bpy, math, os, glob, random
from mathutils import Vector

KAY = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../assets/kaykit"))
OUT = os.environ.get("OUT", "/tmp/backdrop.png")
RESX = int(os.environ.get("RESX", "960"))
RESY = int(os.environ.get("RESY", "1010"))
SAMPLES = int(os.environ.get("SAMPLES", "48"))
SUNROT = math.radians(float(os.environ.get("SUNROT", "0")))
random.seed(7)

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene

# ---------- helpers ----------
def import_model(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    root = bpy.data.objects.new("m", None)
    sc.collection.objects.link(root)
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

def place(rel, loc, rot_deg=0.0, height=None, scale=1.0):
    root, objs = import_model(os.path.join(KAY, rel))
    lo, hi = bounds(objs)
    s = (height / max(0.001, hi.z - lo.z)) if height else scale
    root.scale = (s, s, s)
    root.rotation_euler = (0, 0, math.radians(rot_deg))
    root.location = (loc[0], loc[1], loc[2])
    bpy.context.view_layer.update()
    lo, hi = bounds(objs)
    root.location.z += loc[2] - lo.z          # base sits exactly at loc.z
    bpy.context.view_layer.update()
    for o in objs:
        if o.type == 'MESH':
            for slot in o.material_slots:
                if slot.material and slot.material.use_nodes:
                    for n in slot.material.node_tree.nodes:
                        if n.type == 'BSDF_PRINCIPLED':
                            n.inputs['Roughness'].default_value = 0.85
                            if 'Specular IOR Level' in n.inputs:
                                n.inputs['Specular IOR Level'].default_value = 0.1
    return root, objs

def mat(color, rough=0.9, emit=None, emit_strength=0.0):
    m = bpy.data.materials.new("mat")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs['Base Color'].default_value = (*color, 1)
    b.inputs['Roughness'].default_value = rough
    if emit:
        b.inputs['Emission Color'].default_value = (*emit, 1)
        b.inputs['Emission Strength'].default_value = emit_strength
    return m

def blob(name, loc, scale, material, seg=32):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=seg // 2, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = scale
    bpy.ops.object.shade_smooth()
    o.data.materials.append(material)
    return o

# ---------- world: warm-violet ambient (lighting only); the visible sky is a painted dome ----------
world = bpy.data.worlds.new("w")
sc.world = world
world.use_nodes = True
nt = world.node_tree
for n in list(nt.nodes):
    nt.nodes.remove(n)
bg = nt.nodes.new("ShaderNodeBackground")
bg.inputs['Color'].default_value = (0.46, 0.34, 0.58, 1)
bg.inputs['Strength'].default_value = 0.6
out = nt.nodes.new("ShaderNodeOutputWorld")
nt.links.new(bg.outputs[0], out.inputs['Surface'])

SUN_POS = Vector((-9, 78, 10))

def ramp_stops(ramp, stops):
    els = ramp.color_ramp.elements
    els[0].position, els[0].color = stops[0][0], (*stops[0][1], 1)
    els[1].position, els[1].color = stops[1][0], (*stops[1][1], 1)
    for pos, col in stops[2:]:
        e = els.new(pos)
        e.color = (*col, 1)

def sky_dome():
    bpy.ops.mesh.primitive_uv_sphere_add(segments=64, ring_count=32, radius=400, location=(0, 0, 0))
    d = bpy.context.active_object
    d.name = "skydome"
    m = bpy.data.materials.new("sky")
    m.use_nodes = True
    m.shadow_method = 'NONE'
    t = m.node_tree
    for n in list(t.nodes):
        t.nodes.remove(n)
    tc = t.nodes.new("ShaderNodeTexCoord")
    nrm = t.nodes.new("ShaderNodeVectorMath"); nrm.operation = 'NORMALIZE'
    t.links.new(tc.outputs['Object'], nrm.inputs[0])
    sep = t.nodes.new("ShaderNodeSeparateXYZ")
    t.links.new(nrm.outputs[0], sep.inputs[0])
    mr = t.nodes.new("ShaderNodeMapRange")
    mr.inputs['From Min'].default_value = -1.0
    mr.inputs['From Max'].default_value = 1.0
    t.links.new(sep.outputs['Z'], mr.inputs['Value'])
    ramp = t.nodes.new("ShaderNodeValToRGB")
    # position = 0.5 + 0.5*sin(elevation)
    # The camera only sees about -12..+30 degrees of elevation (positions 0.40..0.75), so the
    # whole sunset has to happen inside that range.
    ramp_stops(ramp, [
        (0.30, (0.20, 0.10, 0.12)), (0.44, (0.62, 0.26, 0.14)),
        (0.495, (1.00, 0.50, 0.18)), (0.52, (1.00, 0.58, 0.28)),
        (0.55, (0.92, 0.34, 0.32)), (0.60, (0.52, 0.20, 0.46)),
        (0.67, (0.16, 0.12, 0.42)), (0.75, (0.06, 0.07, 0.28)), (1.0, (0.03, 0.04, 0.20))])
    t.links.new(mr.outputs[0], ramp.inputs['Fac'])
    # sun glow: tight + wide lobes around the sun direction
    dot = t.nodes.new("ShaderNodeVectorMath"); dot.operation = 'DOT_PRODUCT'
    dot.inputs[1].default_value = SUN_POS.normalized()
    t.links.new(nrm.outputs[0], dot.inputs[0])
    mx = t.nodes.new("ShaderNodeMath"); mx.operation = 'MAXIMUM'; mx.inputs[1].default_value = 0.0
    t.links.new(dot.outputs['Value'], mx.inputs[0])
    tight = t.nodes.new("ShaderNodeMath"); tight.operation = 'POWER'; tight.inputs[1].default_value = 90.0
    wide = t.nodes.new("ShaderNodeMath"); wide.operation = 'POWER'; wide.inputs[1].default_value = 9.0
    t.links.new(mx.outputs[0], tight.inputs[0]); t.links.new(mx.outputs[0], wide.inputs[0])
    wide_s = t.nodes.new("ShaderNodeMath"); wide_s.operation = 'MULTIPLY'; wide_s.inputs[1].default_value = 0.42
    t.links.new(wide.outputs[0], wide_s.inputs[0])
    both = t.nodes.new("ShaderNodeMath"); both.operation = 'ADD'
    t.links.new(tight.outputs[0], both.inputs[0]); t.links.new(wide_s.outputs[0], both.inputs[1])
    gl = t.nodes.new("ShaderNodeValToRGB")
    ramp_stops(gl, [(0.0, (0, 0, 0)), (1.0, (1.0, 0.62, 0.26))])
    t.links.new(both.outputs[0], gl.inputs['Fac'])
    add = t.nodes.new("ShaderNodeMix"); add.data_type = 'RGBA'; add.blend_type = 'ADD'
    add.inputs[0].default_value = 1.0
    t.links.new(ramp.outputs[0], add.inputs[6]); t.links.new(gl.outputs[0], add.inputs[7])
    em = t.nodes.new("ShaderNodeEmission"); em.inputs['Strength'].default_value = 0.9
    t.links.new(add.outputs[2], em.inputs['Color'])
    o = t.nodes.new("ShaderNodeOutputMaterial")
    t.links.new(em.outputs[0], o.inputs['Surface'])
    d.data.materials.append(m)
    d.visible_shadow = False
sky_dome()

def grass(c1, c2, scale=0.35):
    m = bpy.data.materials.new("grass")
    m.use_nodes = True
    t = m.node_tree
    b = t.nodes["Principled BSDF"]
    b.inputs['Roughness'].default_value = 0.95
    tc = t.nodes.new("ShaderNodeTexCoord")
    nz = t.nodes.new("ShaderNodeTexNoise"); nz.inputs['Scale'].default_value = scale; nz.inputs['Detail'].default_value = 3.0
    t.links.new(tc.outputs['Object'], nz.inputs['Vector'])
    r = t.nodes.new("ShaderNodeValToRGB")
    ramp_stops(r, [(0.35, c1), (0.65, c2)])
    t.links.new(nz.outputs['Fac'], r.inputs['Fac'])
    t.links.new(r.outputs[0], b.inputs['Base Color'])
    return m

# ---------- ground + layered hills (aerial perspective: farther = bluer, lighter) ----------
ground = blob("ground", (0, 20, -1.0), (90, 90, 1.0), grass((0.10, 0.24, 0.07), (0.20, 0.36, 0.10), 0.5))
layers = [  # y, x, scale, colour
    (14, -16, (18, 9, 2.2), (0.15, 0.30, 0.09)),
    (18, 17, (20, 9, 2.6), (0.17, 0.31, 0.10)),
    (30, -6, (34, 13, 5.5), (0.25, 0.36, 0.22)),
    (46, 20, (46, 16, 8.5), (0.36, 0.42, 0.36)),
    (60, -25, (52, 18, 10), (0.46, 0.48, 0.52)),
]
for i, (y, x, s, c) in enumerate(layers):
    blob("hill%d" % i, (x, y, -0.6), s, grass(c, tuple(min(1.0, v * 1.28) for v in c), 0.25))

# castle hill
castle_hill = blob("chill", (4.2, 19.5, -2.6), (11.5, 8.0, 3.8), grass((0.15, 0.30, 0.09), (0.26, 0.42, 0.13), 0.6))
CZ = 1.15                                       # top of the hill under the castle

# ---------- castle group ----------
place("hex/building_castle_blue.gltf", (4.4, 19.5, CZ), 172, height=9.6)
place("hex/building_tower_A_blue.gltf", (-0.2, 18.0, CZ - 0.3), 10, height=6.4)
place("hex/building_tower_A_blue.gltf", (9.6, 18.3, CZ - 0.3), -12, height=6.0)
place("hex/building_tower_B_blue.gltf", (12.0, 16.4, CZ - 0.7), 0, height=4.2)
for x in (1.6, 3.2, 4.8, 6.4, 7.8):
    place("hex/wall_straight.gltf", (x, 16.9, CZ - 0.5), 0, height=2.4)

# ---------- distant mountains ----------
place("hex/mountain_A_grass_trees.gltf", (-20, 52, -1.0), 0, height=14)
place("hex/mountain_B_grass_trees.gltf", (30, 58, -1.0), 30, height=17)

# ---------- framing trees + foreground dressing (dark, backlit) ----------
trees = sorted(glob.glob(os.path.join(KAY, "forest", "Tree_*_Color1.gltf")))
def tree(x, y, h, rot=0):
    p = random.choice(trees)
    place("forest/" + os.path.basename(p), (x, y, -0.4), rot, height=h)
for (x, y, h) in [(-8.6, 5.5, 6.0), (-6.2, 9.5, 5.4), (-11.0, 11.5, 7.0), (-3.6, 15.0, 4.6),
                  (7.4, 5.0, 6.8), (9.8, 8.5, 7.8), (5.6, 11.0, 5.6), (12.0, 13.0, 7.0), (-12.5, 16.0, 6.5)]:
    tree(x, y, h, random.uniform(0, 360))
rocks = sorted(glob.glob(os.path.join(KAY, "forest", "Rock_1_*_Color1.gltf")))
for (x, y, h) in [(-4.2, 2.6, 0.7), (4.6, 2.2, 0.6), (-2.0, 4.6, 0.4), (2.8, 5.4, 0.45)]:
    place("forest/" + os.path.basename(random.choice(rocks)), (x, y, -0.5), random.uniform(0, 360), height=h)
bushes = sorted(glob.glob(os.path.join(KAY, "forest", "Bush_*_Color1.gltf")))
for (x, y, h) in [(-6.0, 3.6, 1.1), (6.2, 3.4, 1.0), (-3.0, 7.0, 0.9), (4.0, 8.0, 0.9)]:
    place("forest/" + os.path.basename(random.choice(bushes)), (x, y, -0.5), random.uniform(0, 360), height=h)

# ---------- sun + glow + clouds ----------
sun_pos = SUN_POS
sun = bpy.data.lights.new("sun", 'SUN')
sun.energy = 7.5
sun.color = (1.0, 0.52, 0.24)
sun.angle = math.radians(3.5)
so = bpy.data.objects.new("sun", sun)
sc.collection.objects.link(so)
direction = (Vector((4, 14, 0)) - sun_pos).normalized()
so.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
# soft cool fill from the camera side so backlit surfaces keep some form
fill = bpy.data.lights.new("fill", 'SUN')
fill.energy = 0.35
fill.color = (0.55, 0.62, 0.95)
fo = bpy.data.objects.new("fill", fill)
sc.collection.objects.link(fo)
fo.rotation_euler = Vector((0.3, 1.0, -0.6)).normalized().to_track_quat('-Z', 'Y').to_euler()
# visible sun disc (emissive) and a wider soft halo
disc = blob("sundisc", sun_pos, (1.7, 1.7, 1.7), mat((1, 0.8, 0.5), emit=(1.0, 0.78, 0.45), emit_strength=22))
def cloud_mat(low):
    if low:
        return mat((1.0, 0.62, 0.42), rough=1.0, emit=(1.0, 0.46, 0.24), emit_strength=1.1)
    return mat((0.62, 0.42, 0.66), rough=1.0, emit=(0.55, 0.26, 0.5), emit_strength=0.5)
cm_low, cm_high = cloud_mat(True), cloud_mat(False)
for (x, y, z, sx, sz) in [(-34, 96, 9, 20, 1.5), (-6, 104, 12, 24, 1.6), (26, 98, 10, 20, 1.5), (52, 92, 14, 16, 1.4),
                          (-52, 92, 18, 16, 1.7), (2, 112, 30, 26, 2.6), (-28, 108, 34, 20, 2.2), (34, 106, 36, 18, 2.0),
                          (-14, 100, 22, 18, 1.8), (16, 102, 24, 16, 1.7)]:
    for k in range(5):
        blob("cl", (x + k * sx * 0.27 - sx * 0.5, y + random.uniform(-2, 2), z + random.uniform(-0.5, 0.7) * sz),
             (sx * random.uniform(0.2, 0.34), 3.0, sz * random.uniform(0.6, 1.0)), cm_low if z < 20 else cm_high, 20)

# ---------- camera ----------
cam = bpy.data.cameras.new("cam")
cam.lens = 46
co = bpy.data.objects.new("cam", cam)
sc.collection.objects.link(co)
co.location = (-0.8, -6.0, 1.5)
target = Vector((1.0, 19.0, 5.4))
co.rotation_euler = (target - co.location).to_track_quat('-Z', 'Y').to_euler()
sc.camera = co

# ---------- render ----------
sc.render.engine = 'BLENDER_EEVEE'
ee = sc.eevee
ee.taa_render_samples = SAMPLES
ee.use_gtao = True
ee.gtao_distance = 1.2
ee.gtao_factor = 1.3
ee.use_soft_shadows = True
ee.shadow_cube_size = '2048'
ee.shadow_cascade_size = '2048'
ee.use_bloom = True
ee.bloom_threshold = 1.3
ee.bloom_intensity = 0.12
ee.bloom_radius = 5.0
sc.render.resolution_x = RESX
sc.render.resolution_y = RESY
sc.render.resolution_percentage = 100
sc.render.film_transparent = False
sc.view_settings.view_transform = 'Filmic'
sc.view_settings.look = 'Very High Contrast'
sc.render.image_settings.file_format = 'PNG'
sc.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print("BACKDROP_DONE", OUT)
