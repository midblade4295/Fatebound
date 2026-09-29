# Fatebound terrain art (headless Blender 4.0):
#   xvfb-run -a blender -b --python godot/tools/blender/terrain_art.py
# Env: ONLY=grass,path,rock,bridge   SIZE (texture px, default 1024)   OUTDIR (default assets/terrain)
# Textures are exactly periodic (torus-mapped 4D noise, or geometry rendered over one period), so
# they tile with no seams. Colours follow Kevin's Fat Princess references: lush yellow-green grass
# with lighter cell patches, tan herringbone brick paths, brown-grey rock ledges.
import bpy, os, math, random
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.abspath(os.path.join(HERE, "../.."))
OUTDIR = os.environ.get("OUTDIR", os.path.join(GODOT, "assets/terrain"))
ONLY = [x for x in os.environ.get("ONLY", "").split(",") if x]
SIZE = int(os.environ.get("SIZE", "1024"))
os.makedirs(OUTDIR, exist_ok=True)

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE'
    sc.render.resolution_x = SIZE
    sc.render.resolution_y = SIZE
    sc.render.film_transparent = False
    sc.view_settings.view_transform = 'Standard'
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGB'
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs['Color'].default_value = (0.8, 0.85, 0.95, 1)
    w.node_tree.nodes["Background"].inputs['Strength'].default_value = 0.4
    return sc

def ortho_cam(sc, cx, cy, span):
    cam = bpy.data.cameras.new("cam")
    cam.type = 'ORTHO'
    cam.ortho_scale = span
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    co.location = (cx, cy, 50)
    sc.camera = co

def ramp(nt, stops):
    r = nt.nodes.new("ShaderNodeValToRGB")
    els = r.color_ramp.elements
    els[0].position, els[0].color = stops[0][0], (*stops[0][1], 1)
    els[1].position, els[1].color = stops[1][0], (*stops[1][1], 1)
    for pos, col in stops[2:]:
        e = els.new(pos)
        e.color = (*col, 1)
    return r

def torus_coords(nt, radius):
    """UV (0..1) -> a point on a 4D torus: (R cos 2pi u, R sin 2pi u, R cos 2pi v) + W = R sin 2pi v.
    Any 4D noise sampled there is exactly periodic in u and v."""
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs['UV'], sep.inputs[0])
    def trig(src, fn):
        m = nt.nodes.new("ShaderNodeMath"); m.operation = 'MULTIPLY'; m.inputs[1].default_value = 2 * math.pi
        nt.links.new(src, m.inputs[0])
        t = nt.nodes.new("ShaderNodeMath"); t.operation = fn
        nt.links.new(m.outputs[0], t.inputs[0])
        s = nt.nodes.new("ShaderNodeMath"); s.operation = 'MULTIPLY'; s.inputs[1].default_value = radius
        nt.links.new(t.outputs[0], s.inputs[0])
        return s.outputs[0]
    cu, su = trig(sep.outputs['X'], 'COSINE'), trig(sep.outputs['X'], 'SINE')
    cv, sv = trig(sep.outputs['Y'], 'COSINE'), trig(sep.outputs['Y'], 'SINE')
    comb = nt.nodes.new("ShaderNodeCombineXYZ")
    nt.links.new(cu, comb.inputs[0]); nt.links.new(su, comb.inputs[1]); nt.links.new(cv, comb.inputs[2])
    return comb.outputs[0], sv

def flat_plane_render(sc, build_material, path):
    """Emission-only unit plane filling an ortho camera: the material's colour, exactly."""
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=(0, 0, 0))
    pl = bpy.context.active_object
    m = bpy.data.materials.new("m")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    col = build_material(nt)
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(col, em.inputs['Color'])
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs['Surface'])
    pl.data.materials.append(m)
    ortho_cam(sc, 0, 0, 1.0)
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)

# ---------------- grass ----------------
def grass():
    """Round 7b grass (Kevin: 'more like grass', 'more colourful like the samples'): true green
    (sRGB hue ~110 deg), soft lighter and darker patches, faint wavy lighter lines (the painted
    swirls of the references -- NOT a polygon network, which read as tiles), a blade grain.
    Colours are LINEAR (Blender): (0.05,0.36,0.03) ~ sRGB (63,161,48)."""
    sc = reset()
    def noise4(radius, detail, rough=0.5):
        vec, w = torus_coords(nt_ref[0], radius)
        n = nt_ref[0].nodes.new("ShaderNodeTexNoise"); n.noise_dimensions = '4D'
        n.inputs['Detail'].default_value = detail
        n.inputs['Roughness'].default_value = rough
        nt_ref[0].links.new(vec, n.inputs['Vector']); nt_ref[0].links.new(w, n.inputs['W'])
        return n.outputs['Fac']
    nt_ref = [None]
    def mat(nt):
        nt_ref[0] = nt
        # Soft patches: two octaves of low-frequency noise -> dark/mid/light green.
        patches = noise4(1.1, 2.0)
        base = ramp(nt, [(0.30, (0.045, 0.32, 0.026)), (0.50, (0.085, 0.46, 0.042)), (0.70, (0.14, 0.60, 0.065))])
        nt.links.new(patches, base.inputs['Fac'])
        # Faint wavy lighter lines: where a mid-frequency noise crosses 0.5.
        ridge_n = noise4(1.7, 1.5, 0.4)
        sub = nt.nodes.new("ShaderNodeMath"); sub.operation = 'SUBTRACT'; sub.inputs[1].default_value = 0.5
        nt.links.new(ridge_n, sub.inputs[0])
        ab = nt.nodes.new("ShaderNodeMath"); ab.operation = 'ABSOLUTE'
        nt.links.new(sub.outputs[0], ab.inputs[0])
        line = ramp(nt, [(0.0, (0.34, 0.80, 0.16)), (0.022, (0.0, 0.0, 0.0))])
        nt.links.new(ab.outputs[0], line.inputs['Fac'])
        scr = nt.nodes.new("ShaderNodeMix"); scr.data_type = 'RGBA'; scr.blend_type = 'SCREEN'
        scr.inputs[0].default_value = 0.35
        nt.links.new(base.outputs[0], scr.inputs[6]); nt.links.new(line.outputs[0], scr.inputs[7])
        # Blade grain: dense small cells (tips lighter, roots darker).
        vec2, w2 = torus_coords(nt, 16.0)
        blade = nt.nodes.new("ShaderNodeTexVoronoi"); blade.voronoi_dimensions = '4D'
        nt.links.new(vec2, blade.inputs['Vector']); nt.links.new(w2, blade.inputs['W'])
        bl = ramp(nt, [(0.0, (1.22, 1.20, 1.10)), (0.3, (1.0, 1.0, 1.0)), (0.7, (0.80, 0.86, 0.76))])
        nt.links.new(blade.outputs['Distance'], bl.inputs['Fac'])
        m1 = nt.nodes.new("ShaderNodeMix"); m1.data_type = 'RGBA'; m1.blend_type = 'MULTIPLY'
        m1.inputs[0].default_value = 1.0
        nt.links.new(scr.outputs[2], m1.inputs[6]); nt.links.new(bl.outputs[0], m1.inputs[7])
        # Finer second grain so it doesn't look like dots.
        fine = noise4(30.0, 4.0, 0.6)
        fr = ramp(nt, [(0.4, (0.9, 0.93, 0.88)), (0.6, (1.06, 1.05, 1.02))])
        nt.links.new(fine, fr.inputs['Fac'])
        m2 = nt.nodes.new("ShaderNodeMix"); m2.data_type = 'RGBA'; m2.blend_type = 'MULTIPLY'
        m2.inputs[0].default_value = 1.0
        nt.links.new(m1.outputs[2], m2.inputs[6]); nt.links.new(fr.outputs[0], m2.inputs[7])
        return m2.outputs[2]
    flat_plane_render(sc, mat, os.path.join(OUTDIR, "grass.png"))

# ---------------- rock ----------------
def rock():
    """Cliff face: big stacked slabs (Voronoi stretched along U = horizontal strata), dark cracks,
    warm brown-grey like the reference ledges. U runs along the cliff, V up it."""
    sc = reset()
    def mat(nt):
        vec, w = torus_coords(nt, 0.55)
        # stretch cells horizontally: scale the torus vector's first two components (the U circle)
        st = nt.nodes.new("ShaderNodeVectorMath"); st.operation = 'MULTIPLY'
        st.inputs[1].default_value = (0.45, 0.45, 1.0)
        nt.links.new(vec, st.inputs[0])
        vor = nt.nodes.new("ShaderNodeTexVoronoi"); vor.voronoi_dimensions = '4D'
        vor.feature = 'DISTANCE_TO_EDGE'; vor.inputs['Scale'].default_value = 2.2
        nt.links.new(st.outputs[0], vor.inputs['Vector']); nt.links.new(w, vor.inputs['W'])
        vorc = nt.nodes.new("ShaderNodeTexVoronoi"); vorc.voronoi_dimensions = '4D'
        vorc.inputs['Scale'].default_value = 2.2
        nt.links.new(st.outputs[0], vorc.inputs['Vector']); nt.links.new(w, vorc.inputs['W'])
        vec2, w2 = torus_coords(nt, 3.0)
        nz = nt.nodes.new("ShaderNodeTexNoise"); nz.noise_dimensions = '4D'
        nz.inputs['Detail'].default_value = 4.0
        nt.links.new(vec2, nz.inputs['Vector']); nt.links.new(w2, nz.inputs['W'])
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(vorc.outputs['Color'], sep.inputs[0])
        stone = ramp(nt, [(0.0, (0.16, 0.10, 0.065)), (0.5, (0.24, 0.16, 0.10)), (1.0, (0.33, 0.24, 0.16))])
        nt.links.new(sep.outputs[0], stone.inputs['Fac'])
        crack = ramp(nt, [(0.0, (0.02, 0.012, 0.008)), (0.05, (0.35, 0.3, 0.26)), (0.11, (1, 1, 1))])
        nt.links.new(vor.outputs['Distance'], crack.inputs['Fac'])
        m1 = nt.nodes.new("ShaderNodeMix"); m1.data_type = 'RGBA'; m1.blend_type = 'MULTIPLY'
        m1.inputs[0].default_value = 1.0
        nt.links.new(stone.outputs[0], m1.inputs[6]); nt.links.new(crack.outputs[0], m1.inputs[7])
        grain = ramp(nt, [(0.3, (0.82, 0.82, 0.82)), (0.7, (1.1, 1.06, 1.0))])
        nt.links.new(nz.outputs['Fac'], grain.inputs['Fac'])
        m2 = nt.nodes.new("ShaderNodeMix"); m2.data_type = 'RGBA'; m2.blend_type = 'MULTIPLY'
        m2.inputs[0].default_value = 1.0
        nt.links.new(m1.outputs[2], m2.inputs[6]); nt.links.new(grain.outputs[0], m2.inputs[7])
        return m2.outputs[2]
    flat_plane_render(sc, mat, os.path.join(OUTDIR, "rock.png"))

# ---------------- herringbone path ----------------
def path():
    """Real beveled bricks in a 90-degree herringbone (2x1 bricks; horizontal bricks on the lattice
    (1,1)/(2,-2), vertical bricks offset (-1,0) -- verified to cover the plane exactly with period
    4x4). Rendered top-down over exactly one 4x4 period with overscan, so AO/shading at the edges
    comes from the neighbouring bricks and the tile has no seams."""
    sc = reset()
    random.seed(11)
    grout = bpy.data.materials.new("grout")
    grout.use_nodes = True
    grout.node_tree.nodes["Principled BSDF"].inputs['Base Color'].default_value = (0.13, 0.08, 0.045, 1)
    grout.node_tree.nodes["Principled BSDF"].inputs['Roughness'].default_value = 1.0
    bpy.ops.mesh.primitive_plane_add(size=20, location=(2, 2, -0.02))
    bpy.context.active_object.data.materials.append(grout)
    brick_mats = []
    # Blender colours are LINEAR: these read as tan/terracotta sRGB ~(195,150,105).
    for c in [(0.55, 0.34, 0.17), (0.49, 0.29, 0.14), (0.60, 0.39, 0.20), (0.44, 0.26, 0.12), (0.53, 0.33, 0.16)]:
        m = bpy.data.materials.new("brick")
        m.use_nodes = True
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs['Base Color'].default_value = (*c, 1)
        b.inputs['Roughness'].default_value = 0.9
        brick_mats.append(m)
    gap = 0.06
    flat = os.environ.get("PATH_FLAT", "") == "1"      # control render: no jitter, one colour
    def brick(x0, y0, w, h):
        # Colour, tilt and height come from the brick's position WITHIN the 4x4 period, so the copy
        # of a brick one period away is identical and the halves cut by the tile edge match.
        rnd = random.Random(hash((x0 % 4, y0 % 4, w)) & 0xffffffff)
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x0 + w / 2, y0 + h / 2, 0.06))
        o = bpy.context.active_object
        o.scale = (w - gap, h - gap, 0.14)
        bpy.ops.object.transform_apply(scale=True)
        bev = o.modifiers.new("b", 'BEVEL'); bev.width = 0.07; bev.segments = 3
        if not flat:
            o.rotation_euler.z = rnd.uniform(-0.012, 0.012)
            o.location.z += rnd.uniform(-0.01, 0.01)
        o.data.materials.append(brick_mats[0] if flat else rnd.choice(brick_mats))
    for m in range(-8, 9):
        for n in range(-6, 7):
            ox, oy = m + 2 * n, m - 2 * n
            for (bx, by, w, h) in [(ox, oy, 2, 1), (ox - 1, oy, 1, 2)]:
                if -2 <= bx <= 6 and -2 <= by <= 6:
                    brick(bx, by, w, h)
    sun = bpy.data.lights.new("sun", 'SUN'); sun.energy = 2.2; sun.angle = math.radians(20)
    so = bpy.data.objects.new("sun", sun); sc.collection.objects.link(so)
    so.rotation_euler = (math.radians(35), 0, math.radians(30))
    ee = sc.eevee
    ee.taa_render_samples = 32
    ee.use_gtao = True; ee.gtao_distance = 0.25; ee.gtao_factor = 1.4
    ee.use_overscan = True; ee.overscan_size = 0.25
    ee.use_soft_shadows = True
    sc.world.node_tree.nodes["Background"].inputs['Strength'].default_value = 0.35
    ortho_cam(sc, 2.0, 2.0, 4.0)                  # exactly one 4x4 period
    sc.render.filepath = os.path.join(OUTDIR, "path.png")
    bpy.ops.render.render(write_still=True)

# ---------------- bridge ----------------
def bridge():
    """Wooden bridge, +Z up in Blender (glTF export converts to Godot's Y-up). Runs along Blender Y
    (Godot Z), 10 m long, 4.4 m deck, gently arched, posts + rails both sides, stone footings.
    Origin at the deck centre at bank height; the deck top rises to +0.55 m at mid-span."""
    reset()
    random.seed(5)
    def pmat(name, c, rough=0.85):
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs['Base Color'].default_value = (*c, 1)
        b.inputs['Roughness'].default_value = rough
        return m
    planks = [pmat("plank%d" % i, c) for i, c in enumerate([(0.55, 0.34, 0.18), (0.50, 0.30, 0.16), (0.60, 0.38, 0.20)])]
    dark = pmat("beam", (0.36, 0.21, 0.11))
    stone = pmat("stone", (0.55, 0.53, 0.50), 0.95)
    L, W, ARCH = 10.0, 4.4, 0.55
    def arch_z(y):
        t = y / (L / 2)
        return ARCH * (1 - t * t)
    def box(name, loc, size, rot=(0, 0, 0), mat=dark, bevel=0.03):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
        o = bpy.context.active_object
        o.name = name
        o.scale = size
        o.rotation_euler = rot
        bpy.ops.object.transform_apply(scale=True)
        if bevel > 0:
            b = o.modifiers.new("b", 'BEVEL'); b.width = bevel; b.segments = 2
        o.data.materials.append(mat)
        return o
    n = 22
    for i in range(n):
        y = -L / 2 + (i + 0.5) * L / n
        slope = -2 * ARCH * y / ((L / 2) ** 2)
        box("plank", (random.uniform(-0.05, 0.05), y, arch_z(y) + 0.06), (W + random.uniform(-0.1, 0.12), L / n - 0.05, 0.12),
            rot=(math.atan(slope), 0, random.uniform(-0.02, 0.02)), mat=random.choice(planks), bevel=0.025)
    for sx in (-1, 1):
        for k in range(5):                               # under-deck beams
            y0, y1 = -L / 2 + k * L / 5, -L / 2 + (k + 1) * L / 5
            ym = (y0 + y1) / 2
            dz = arch_z(y1) - arch_z(y0)
            box("stringer", (sx * (W / 2 - 0.25), ym, arch_z(ym) - 0.1), (0.22, L / 5 + 0.1, 0.22), rot=(math.atan2(dz, L / 5), 0, 0))
        for k in range(6):                               # posts
            y = -L / 2 + 0.3 + k * (L - 0.6) / 5
            box("post", (sx * (W / 2 - 0.12), y, arch_z(y) + 0.55), (0.22, 0.22, 1.05))
        for h in (0.95, 0.55):                           # rails
            for k in range(5):
                y0 = -L / 2 + 0.3 + k * (L - 0.6) / 5
                y1 = y0 + (L - 0.6) / 5
                ym = (y0 + y1) / 2
                dz = arch_z(y1) - arch_z(y0)
                box("rail", (sx * (W / 2 - 0.12), ym, arch_z(ym) + h), (0.12, (L - 0.6) / 5 + 0.08, 0.12), rot=(math.atan2(dz, L / 5), 0, 0))
        for sy in (-1, 1):                               # stone footings at the banks
            box("footing", (sx * (W / 2 - 0.2), sy * (L / 2 - 0.3), -0.35), (0.9, 1.0, 0.9), mat=stone, bevel=0.1)
    for o in bpy.data.objects:
        if o.type == 'MESH':
            o.select_set(True)
            bpy.context.view_layer.objects.active = o
    bpy.ops.object.convert(target='MESH')                # apply bevels
    bpy.ops.object.join()
    bpy.context.active_object.name = "bridge"
    out = os.path.join(OUTDIR, "bridge.glb")
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=False, export_apply=True)

for name, fn in [("grass", grass), ("rock", rock), ("path", path), ("bridge", bridge)]:
    if ONLY and name not in ONLY:
        continue
    fn()
    print("TERRAIN_ART_DONE", name, flush=True)
