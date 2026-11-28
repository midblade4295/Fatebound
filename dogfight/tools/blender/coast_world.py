"""Coastal countryside generator for Squadron Skies (Blender 4.x, bpy).

Run it from Blender's Scripting tab (Open > Run Script), or headless:
    blender --background --python coast_world.py
Everything it makes goes into three collections it owns and rebuilds on
every run: Coast_World (terrain, runways, markers), Coast_Assets (tree,
boulder, cottage, each at the world origin) and Coast_Preview (sea, sun and
camera for a look in the viewport: not exported).

It then writes four files into EXPORT_DIR:
    coast_terrain.glb   terrain + runways + runway paint + airfield markers
    coast_tree.glb      coast_boulder.glb      coast_cottage.glb

Units are metres, 1:1. Blender is Z-up; glTF/Godot are Y-up, and Blender's
+Y becomes Godot's -Z, which the exporter takes care of.

Terrain vertex colours (attribute "Col", exported as COLOR_0):
    R  lush grass on flat and gently rolling ground
    G  farmland: patchwork fields of wheat
    B  chalk: the cliff faces, and the pale sea bed at their feet
    A  a random 0.25-1 per field, to tint one field differently from the next
R + G + B is always 1.
"""

import math
import os
import random

import bpy  # first: as a Python module (pip install bpy) it is what makes bmesh importable
import bmesh
import numpy as np
from mathutils import Matrix, Vector

# --------------------------------------------------------------------------
# Settings
# --------------------------------------------------------------------------
SEED = 7
TERRAIN_SIZE = 8000.0      # the terrain is this many metres square, centred on the origin
GRID = 320                 # cells per side: 25 m apart
SEA_LEVEL = 0.0
COAST_X = 1500.0           # the cliffs run north-south about here; the sea is east (+X)
COAST_WANDER = 420.0       # how far headlands and bays stray from that line
CLIFF_LEAN = 4.0           # the foot of the cliff is this far out from its lip: sheer
LAND_BASE = 78.0           # typical height of the land, so the cliffs are about this tall
HILL_HEIGHT = 78.0         # hills rise and fall this much either side of it
FOLD_HEIGHT = 22.0         # with smaller folds and hollows on top
INLAND_RISE = 0.03         # and the country climbs gently toward the far (west) side

# Runways, to real-world scale. A wartime RAF hard runway was 50 yards wide.
# Fighter stations had a main runway of about 1,500-1,700 yards and two
# subsidiaries of about 1,100, laid out as a triangle ("A"). (The Class A
# bomber standard was longer: 2,000 yards and two of 1,400.)
YARD = 0.9144
RUNWAY_WIDTH = 50.0 * YARD            # 45.7 m
RUNWAY_MAIN = 1600.0 * YARD           # 1,463 m
RUNWAY_SECONDARY = 1100.0 * YARD      # 1,006 m
RUNWAY_LIFT = 0.12                    # the surface sits this far proud of the grass
# name, centre (x, y), heading of the main runway in degrees clockwise from +Y.
# Each main runway points at the middle of the map, where the two sides meet.
AIRFIELDS = [("Blue", (-700.0, -2250.0), 0.0), ("Red", (-700.0, 2250.0), 180.0)]
FLAT_INNER = 140.0         # ground within this of a runway is dead level
FLAT_OUTER = 560.0         # and has blended back into the hills by here

EXPORT = True
_here = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() and os.path.isfile(__file__) else ""
EXPORT_DIR = os.path.normpath(os.path.join(_here, "..", "..", "assets", "models", "coast")) if _here else \
    os.path.join(os.path.dirname(bpy.data.filepath) or os.path.expanduser("~"), "coast_export")
PREVIEW_IMAGE = os.environ.get("COAST_PREVIEW", "")   # a path here renders a picture (Cycles, CPU)

COLLECTIONS = ("Coast_World", "Coast_Assets", "Coast_Preview")


# --------------------------------------------------------------------------
# Noise (plain numpy, so the result is the same in every Blender version)
# --------------------------------------------------------------------------
def _lattice(ix, iy, seed):
    """A repeatable random number, 0..1, for each integer grid point."""
    n = (ix.astype(np.int64) * 374761393 + iy.astype(np.int64) * 668265263 + seed * 1442695041) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFFFFFF) / 4294967295.0


def value_noise(x, y, seed):
    ix, iy = np.floor(x), np.floor(y)
    fx, fy = x - ix, y - iy
    fx, fy = fx * fx * (3.0 - 2.0 * fx), fy * fy * (3.0 - 2.0 * fy)
    a, b = _lattice(ix, iy, seed), _lattice(ix + 1, iy, seed)
    c, d = _lattice(ix, iy + 1, seed), _lattice(ix + 1, iy + 1, seed)
    return (a + (b - a) * fx) + ((c + (d - c) * fx) - (a + (b - a) * fx)) * fy


def fbm(x, y, scale, octaves, seed):
    """Layered noise, about -1..1, whose biggest features are `scale` metres across."""
    total, amplitude, reach = 0.0, 1.0, 0.0
    for octave in range(octaves):
        frequency = (2.0 ** octave) / scale
        total = total + amplitude * (value_noise(x * frequency, y * frequency, seed + octave * 31) * 2.0 - 1.0)
        reach += amplitude
        amplitude *= 0.5
    return total / reach


def smoothstep(low, high, value):
    t = np.clip((value - low) / (high - low), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


# --------------------------------------------------------------------------
# Scene helpers
# --------------------------------------------------------------------------
def reset_collections():
    """Removes whatever an earlier run made, and returns fresh collections."""
    made = {}
    for name in COLLECTIONS:
        old = bpy.data.collections.get(name)
        if old is not None:
            for obj in list(old.objects):
                data = obj.data
                bpy.data.objects.remove(obj, do_unlink=True)
                if data is not None and data.users == 0 and isinstance(data, bpy.types.Mesh):
                    bpy.data.meshes.remove(data)
            bpy.data.collections.remove(old)
        made[name] = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(made[name])
    return made


def material(name, colour, roughness=0.9):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*colour, 1.0)
    shader.inputs["Roughness"].default_value = roughness
    mat.diffuse_color = (*colour, 1.0)
    return mat


def terrain_material():
    """Shows the vertex colours as grass, wheat and chalk, as the Godot shader will."""
    mat = material("Terrain", (0.30, 0.62, 0.16))
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    shader = nodes["Principled BSDF"]
    for node in [n for n in nodes if n.name.startswith("Coast")]:
        nodes.remove(node)
    paint = nodes.new("ShaderNodeVertexColor")
    paint.name, paint.layer_name = "CoastPaint", "Col"
    split = nodes.new("ShaderNodeSeparateColor")
    split.name = "CoastSplit"
    links.new(paint.outputs["Color"], split.inputs["Color"])
    previous = None
    for index, (channel, colour) in enumerate((("Green", (0.93, 0.70, 0.22)), ("Blue", (0.94, 0.95, 0.92)))):
        mix = nodes.new("ShaderNodeMix")
        mix.name, mix.data_type = "CoastMix%d" % index, 'RGBA'
        links.new(split.outputs[channel], mix.inputs[0])
        if previous is None:
            mix.inputs[6].default_value = (0.30, 0.62, 0.16, 1.0)
        else:
            links.new(previous.outputs[2], mix.inputs[6])
        mix.inputs[7].default_value = (*colour, 1.0)
        previous = mix
    links.new(previous.outputs[2], shader.inputs["Base Color"])
    return mat


def new_object(name, mesh, collection, materials=()):
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    for mat in materials:
        mesh.materials.append(mat)
    return obj


def finish(bm, name, smooth_angle=None):
    """Turns a bmesh into a mesh, shaded smooth except across sharp edges."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    if len(mesh.color_attributes) > 0:
        # Mark the colours as the ones to use, or the glTF exporter leaves them out.
        mesh.color_attributes.active_color = mesh.color_attributes[0]
        mesh.color_attributes.render_color_index = 0
    if smooth_angle is not None and hasattr(mesh, "set_sharp_from_angle"):
        mesh.set_sharp_from_angle(angle=math.radians(smooth_angle))
    return mesh


# --------------------------------------------------------------------------
# Airfields and runways
# --------------------------------------------------------------------------
def runway_layout(centre, heading_deg):
    """The three runways of one airfield as (name, centre, heading, length)."""
    turn = math.radians(heading_deg)
    along = Vector((math.sin(turn), math.cos(turn)))        # the way the main runway points
    across = Vector((along.y, -along.x))
    middle = Vector(centre)
    runways = [("Main", middle, heading_deg, RUNWAY_MAIN)]
    # The two subsidiaries cross the main runway 400 m either side of its
    # middle and meet off to one side of it: the letter A.
    for label, side in (("SecondaryA", 1.0), ("SecondaryB", -1.0)):
        runways.append((label, middle - across * 260.0 + along * 250.0 * side, heading_deg + 60.0 * side, RUNWAY_SECONDARY))
    return runways


def runway_ends(centre, heading_deg, length):
    turn = math.radians(heading_deg)
    along = Vector((math.sin(turn), math.cos(turn)))
    return centre - along * length * 0.5, centre + along * length * 0.5


def distance_to_runways(x, y, runways):
    """Distance from every terrain point to the nearest runway centre line."""
    nearest = np.full(x.shape, np.inf)
    for _label, centre, heading, length in runways:
        start, end = runway_ends(centre, heading, length)
        dx, dy = end.x - start.x, end.y - start.y
        t = np.clip(((x - start.x) * dx + (y - start.y) * dy) / (dx * dx + dy * dy), 0.0, 1.0)
        nearest = np.minimum(nearest, np.hypot(x - (start.x + dx * t), y - (start.y + dy * t)))
    return nearest


def strip_mesh(name, centre, heading_deg, length, width, height, step=None):
    """A flat ribbon of quads: a runway, or a line painted on one."""
    turn = math.radians(heading_deg)
    along = Vector((math.sin(turn), math.cos(turn)))
    across = Vector((along.y, -along.x))
    rows = max(int(math.ceil(length / step)), 1) if step else 1
    verts, faces, uvs = [], [], []
    for row in range(rows + 1):
        v = -length * 0.5 + length * row / rows
        for side in (-0.5, 0.5):
            point = centre + along * v + across * (width * side)
            verts.append((point.x, point.y, height))
            uvs.append((side + 0.5, (v + length * 0.5) / width))
    for row in range(rows):
        base = row * 2
        faces.append((base, base + 1, base + 3, base + 2))
    return verts, faces, uvs


def build_airfield(team, centre, heading, elevation, collection, tarmac, paint):
    surface = elevation + RUNWAY_LIFT
    verts, faces, uvs, paint_verts, paint_faces = [], [], [], [], []
    for label, runway_centre, runway_heading, length in runway_layout(centre, heading):
        v, f, uv = strip_mesh(label, runway_centre, runway_heading, length, RUNWAY_WIDTH, surface, 25.0)
        faces += [tuple(index + len(verts) for index in face) for face in f]
        verts += v
        uvs += uv
        # Paint: a dashed centre line (30 m on, 30 m off) and a bar at each threshold.
        turn = math.radians(runway_heading)
        along = Vector((math.sin(turn), math.cos(turn)))
        marks = [(runway_centre + along * offset, 30.0, 0.9) for offset in np.arange(-length * 0.5 + 60.0, length * 0.5 - 60.0, 60.0)]
        marks += [(runway_centre + along * (length * 0.5 - 12.0) * end, 3.0, RUNWAY_WIDTH - 6.0) for end in (-1.0, 1.0)]
        for mark_centre, mark_length, mark_width in marks:
            v, f, _uv = strip_mesh("", mark_centre, runway_heading, mark_length, mark_width, surface + 0.04)
            paint_faces += [tuple(index + len(paint_verts) for index in face) for face in f]
            paint_verts += v
    mesh = bpy.data.meshes.new("Runways_%s" % team)
    mesh.from_pydata(verts, [], faces)
    layer = mesh.uv_layers.new(name="UVMap")
    for loop in mesh.loops:
        layer.data[loop.index].uv = uvs[loop.vertex_index]
    new_object("Runways_%s" % team, mesh, collection, (tarmac,))
    lines = bpy.data.meshes.new("RunwayPaint_%s" % team)
    lines.from_pydata(paint_verts, [], paint_faces)
    new_object("RunwayPaint_%s" % team, lines, collection, (paint,))
    # Markers the game can read: where the airfield is and which way to take off.
    start, _end = runway_ends(Vector(centre), heading, RUNWAY_MAIN)
    for marker_name, place in (("Airfield_%s" % team, Vector(centre)), ("Airfield_%s_RunwayStart" % team, start)):
        marker = bpy.data.objects.new(marker_name, None)
        marker.empty_display_type, marker.empty_display_size = 'ARROWS', 60.0
        marker.location = (place.x, place.y, surface)
        marker.rotation_euler = (0.0, 0.0, -math.radians(heading))   # its +Y is the take-off direction
        marker["runway_length_m"], marker["runway_width_m"] = RUNWAY_MAIN, RUNWAY_WIDTH
        collection.objects.link(marker)


# --------------------------------------------------------------------------
# Terrain
# --------------------------------------------------------------------------
def build_terrain(collection):
    count = GRID + 1
    half = TERRAIN_SIZE * 0.5
    line = np.linspace(-half, half, count)
    y = np.repeat(line[:, None], count, axis=1)          # y[row, column]; rows run south to north

    # The coast: a wandering line, with the sea to the east of it. One column
    # of the grid is laid along that line for the whole length of the map and
    # the next column CLIFF_LEAN further out, so the drop between the two is
    # sheer. Every row is stretched a little to fit: land columns from the
    # west edge to the cliff, sea columns from the cliff to the east edge.
    coast = COAST_X + COAST_WANDER * fbm(line * 0.0, line, 2300.0, 3, SEED + 7) + 90.0 * fbm(line * 0.0, line, 520.0, 2, SEED + 19)
    lip = int(round((COAST_X + half) / TERRAIN_SIZE * GRID))
    x = np.empty_like(y)
    x[:, :lip + 1] = -half + (coast[:, None] + half) * np.linspace(0.0, 1.0, lip + 1)[None, :]
    x[:, lip + 1:] = coast[:, None] + CLIFF_LEAN + (half - coast[:, None] - CLIFF_LEAN) * np.linspace(0.0, 1.0, GRID - lip)[None, :]
    from_coast = x - coast[:, None]                      # negative on land

    # Rolling country: big soft hills, smaller folds on top, rising inland.
    land = LAND_BASE + HILL_HEIGHT * fbm(x, y, 1900.0, 5, SEED) + FOLD_HEIGHT * fbm(x, y, 620.0, 3, SEED + 101)
    land += INLAND_RISE * np.clip(-(x + 1400.0), 0.0, None)
    land = np.maximum(land, 24.0)

    # Each airfield is levelled: dead flat by the runways, easing back into the hills.
    airfield_distance = np.full(x.shape, np.inf)
    elevations = {}
    for team, centre, heading in AIRFIELDS:
        runways = runway_layout(centre, heading)
        distance = distance_to_runways(x, y, runways)
        elevations[team] = round(float(land[distance < FLAT_INNER].mean()), 1)
        level = 1.0 - smoothstep(FLAT_INNER, FLAT_OUTER, distance)
        land = land + (elevations[team] - land) * level
        airfield_distance = np.minimum(airfield_distance, distance)

    # East of the cliff: the sea bed, shelving away from its foot.
    height = np.where(from_coast > 0.0, np.maximum(-5.0 - 0.035 * from_coast, -70.0), land)

    # Build the mesh.
    verts = np.stack((x.ravel(), y.ravel(), height.ravel()), axis=1)
    cell = np.arange(GRID * GRID)
    corner = cell + cell // GRID            # index of each cell's south-west vertex
    faces = np.stack((corner, corner + 1, corner + count + 1, corner + count), axis=1)
    mesh = bpy.data.meshes.new("Terrain")
    mesh.vertices.add(len(verts))
    mesh.vertices.foreach_set("co", verts.ravel())
    mesh.loops.add(faces.size)
    mesh.loops.foreach_set("vertex_index", faces.ravel())
    mesh.polygons.add(len(faces))
    mesh.polygons.foreach_set("loop_start", np.arange(0, faces.size, 4))
    mesh.polygons.foreach_set("loop_total", np.full(len(faces), 4))
    mesh.polygons.foreach_set("use_smooth", np.ones(len(faces), dtype=bool))
    mesh.update(calc_edges=True)
    mesh.validate()

    # ---- Vertex colours, from height and slope -----------------------------
    vertex_normals = np.empty(len(verts) * 3)
    mesh.vertices.foreach_get("normal", vertex_normals)
    vertex_slope = np.degrees(np.arccos(np.clip(vertex_normals.reshape(-1, 3)[:, 2], -1.0, 1.0)))
    face_normals = np.empty(len(faces) * 3)
    mesh.polygons.foreach_get("normal", face_normals)
    face_slope = np.degrees(np.arccos(np.clip(face_normals.reshape(-1, 3)[:, 2], -1.0, 1.0)))

    # Farmland: a patchwork of fields, turned a little off north. About a
    # third are wheat. They keep to gentle ground, clear of cliff and airfield.
    turn = math.radians(24.0)
    u = (x * math.cos(turn) + y * math.sin(turn)) / 190.0
    v = (-x * math.sin(turn) + y * math.cos(turn)) / 150.0
    field_id = _lattice(np.floor(u), np.floor(v), SEED + 5)
    hedge = np.minimum(np.minimum(u % 1.0, 1.0 - u % 1.0) * 190.0, np.minimum(v % 1.0, 1.0 - v % 1.0) * 150.0)
    farmed = fbm(x, y, 1500.0, 2, SEED + 55) > -0.15
    wheat = (field_id < 0.36) & farmed & (hedge > 9.0) & (from_coast < -160.0) & (airfield_distance > 300.0)
    wheat = wheat.ravel() & (vertex_slope < 9.0) & (height.ravel() > 22.0)
    tint = np.where(wheat, 0.25 + 0.75 * _lattice(np.floor(u), np.floor(v), SEED + 6).ravel(), 1.0)

    loop_vertex = faces.ravel()
    loop_face = np.repeat(np.arange(len(faces)), 4)
    # Chalk is decided face by face, so the cliff is white right up to its
    # lip and the turf on top stays green right up to the edge.
    chalk = smoothstep(38.0, 58.0, face_slope)[loop_face]
    chalk = np.maximum(chalk, (verts[loop_vertex, 2] < SEA_LEVEL - 1.0).astype(float))
    green = wheat[loop_vertex].astype(float) * (1.0 - chalk)
    colours = np.stack((1.0 - chalk - green, green, chalk, tint[loop_vertex]), axis=1)
    paint = mesh.color_attributes.new(name="Col", type='BYTE_COLOR', domain='CORNER')
    paint.data.foreach_set("color", colours.ravel())
    mesh.color_attributes.active_color = paint
    mesh.color_attributes.render_color_index = 0

    terrain = new_object("Terrain", mesh, collection, (terrain_material(),))
    share = [float(colours[:, channel].mean()) for channel in range(3)]
    land_heights = height[from_coast <= 0.0]
    print("Terrain: %d vertices, %d faces; land %.0f to %.0f m; grass %.0f%%, wheat %.0f%%, chalk %.0f%%" % (
        len(verts), len(faces), land_heights.min(), land_heights.max(), share[0] * 100, share[1] * 100, share[2] * 100))
    return terrain, elevations


# --------------------------------------------------------------------------
# The three modular assets, each built at the world origin, standing on z = 0
# --------------------------------------------------------------------------
def build_tree(collection):
    """A tapered trunk under a canopy of overlapping spheres. About 8 m tall."""
    rng = random.Random(SEED + 1)
    bm = bmesh.new()
    paint = bm.loops.layers.color.new("Col")
    bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.55, radius2=0.26, depth=3.6,
                          matrix=Matrix.Translation((0.0, 0.0, 1.8)))
    for face in bm.faces:
        face.material_index = 0
        for loop in face.loops:
            loop[paint] = (0.0, 0.0, 0.0, 1.0)
    blobs = [((0.0, 0.0, 5.3), 2.3), ((1.5, 0.4, 4.6), 1.6), ((-1.4, 0.7, 4.7), 1.7),
             ((0.3, -1.5, 4.5), 1.6), ((-0.5, 1.3, 5.9), 1.5), ((0.9, -0.3, 6.4), 1.4)]
    for centre, radius in blobs:
        shape = Matrix.Translation(centre) @ Matrix.Diagonal((radius, radius, radius * 0.86, 1.0))
        puff = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0, matrix=shape)
        shade = rng.uniform(0.0, 1.0)
        for vert in puff["verts"]:
            for face in vert.link_faces:
                face.material_index = 1
            for loop in vert.link_loops:
                # For the foliage shader: R = how high in the canopy (0 bottom, 1 top),
                # G = a different number for each puff, B = 1 marks a leaf (0 = bark).
                loop[paint] = (min(max((vert.co.z - 3.0) / 4.6, 0.0), 1.0), shade, 1.0, 1.0)
    mesh = finish(bm, "Tree", 50.0)
    return new_object("Tree", mesh, collection, (material("Bark", (0.36, 0.22, 0.12)), material("Canopy", (0.20, 0.55, 0.16))))


def build_boulder(collection):
    """A low-poly rock with its edges knocked off. About 2.6 m across."""
    rng = random.Random(SEED + 2)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
    for vert in bm.verts:
        vert.co *= rng.uniform(0.82, 1.18)
        vert.co.x *= 1.3
        vert.co.z = max(vert.co.z * 0.8, -0.38)         # squat, with a flat base to sit on
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=0.09, segments=2, profile=0.5, affect='EDGES')
    lowest = min(vert.co.z for vert in bm.verts)
    for vert in bm.verts:
        vert.co.z -= lowest
    mesh = finish(bm, "Boulder", 35.0)
    return new_object("Boulder", mesh, collection, (material("Rock", (0.58, 0.56, 0.52)),))


def _box(bm, size, centre, mat_index, bevel=0.0):
    made = bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation(centre) @ Matrix.Diagonal((*size, 1.0)))
    faces = {face for vert in made["verts"] for face in vert.link_faces}
    # The material goes on first: the faces a bevel adds take it from their neighbours.
    for face in faces:
        face.material_index = mat_index
    if bevel > 0.0:
        edges = list({edge for face in faces for edge in face.edges})
        bmesh.ops.bevel(bm, geom=edges, offset=bevel, segments=2, profile=0.5, affect='EDGES')


def build_cottage(collection):
    """A small cottage under a roof far too big for it. 5 x 4 m, 6.4 m to the ridge."""
    bm = bmesh.new()
    _box(bm, (5.0, 4.0, 2.6), (0.0, 0.0, 1.3), 0, 0.12)                       # walls
    # The roof: a steep gable with deep eaves, taller than the walls under it.
    half_x, half_y, eave, ridge = 3.3, 2.75, 2.25, 6.4
    corners = [(-half_x, -half_y, eave), (half_x, -half_y, eave), (half_x, half_y, eave), (-half_x, half_y, eave),
               (-half_x * 0.92, 0.0, ridge), (half_x * 0.92, 0.0, ridge)]
    v = [bm.verts.new(corner) for corner in corners]
    roof = [bm.faces.new(order) for order in ((v[0], v[1], v[5], v[4]), (v[2], v[3], v[4], v[5]),
                                              (v[1], v[2], v[5]), (v[3], v[0], v[4]), (v[3], v[2], v[1], v[0]))]
    for face in roof:
        face.material_index = 1
    bmesh.ops.bevel(bm, geom=list({edge for face in roof for edge in face.edges}), offset=0.14, segments=2, profile=0.5, affect='EDGES')
    _box(bm, (0.8, 0.8, 2.6), (1.5, 0.9, 5.6), 4, 0.08)                       # chimney
    _box(bm, (1.0, 0.16, 1.9), (-0.9, -2.02, 0.95), 2, 0.04)                  # door
    for place in ((1.2, -2.02, 1.5), (-2.52, 0.0, 1.5), (2.52, 0.0, 1.5)):   # windows
        size = (0.95, 0.14, 0.95) if abs(place[1]) > 1.0 else (0.14, 0.95, 0.95)
        _box(bm, size, place, 3, 0.03)
    mesh = finish(bm, "Cottage", 40.0)
    mats = (material("CottageWall", (0.93, 0.87, 0.74)), material("CottageRoof", (0.83, 0.36, 0.17)),
            material("CottageWood", (0.40, 0.25, 0.13)), material("CottageWindow", (0.55, 0.80, 0.92), 0.3),
            material("CottageStone", (0.62, 0.60, 0.57)))
    return new_object("Cottage", mesh, collection, mats)


# --------------------------------------------------------------------------
# Export and preview
# --------------------------------------------------------------------------
def export_glb(objects, filename):
    os.makedirs(EXPORT_DIR, exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    path = os.path.join(EXPORT_DIR, filename)
    options = dict(filepath=path, export_format='GLB', use_selection=True, export_apply=True, export_yup=True, export_extras=True)
    # Vertex colours: Blender 4.2+ only writes them when asked; 4.0/4.1 use an older switch.
    for extra in (dict(export_vertex_color='ACTIVE', export_all_vertex_colors=False), dict(export_colors=True), dict()):
        try:
            bpy.ops.export_scene.gltf(**options, **extra)
            break
        except TypeError:
            continue
    print("Wrote %s (%.1f MB)" % (path, os.path.getsize(path) / 1048576.0))


def build_preview(collection, render_to):
    """A sea, a sun and a camera on the headland, to look at the result in Blender."""
    sea = bpy.data.meshes.new("PreviewSea")
    reach = TERRAIN_SIZE * 2.0
    sea.from_pydata([(-reach, -reach, SEA_LEVEL), (reach, -reach, SEA_LEVEL), (reach, reach, SEA_LEVEL), (-reach, reach, SEA_LEVEL)], [], [(0, 1, 2, 3)])
    new_object("PreviewSea", sea, collection, (material("PreviewSea", (0.05, 0.50, 0.66), 0.25),))
    sun = bpy.data.objects.new("PreviewSun", bpy.data.lights.new("PreviewSun", 'SUN'))
    sun.data.energy, sun.data.color = 2.6, (1.0, 0.95, 0.84)
    sun.rotation_euler = (math.radians(52.0), 0.0, math.radians(-125.0))
    collection.objects.link(sun)
    camera = bpy.data.objects.new("PreviewCamera", bpy.data.cameras.new("PreviewCamera"))
    camera.data.lens, camera.data.clip_end = 24.0, 30000.0
    camera.location = (2500.0, -3300.0, 330.0)
    camera.rotation_euler = (Vector((300.0, 300.0, 40.0)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
    collection.objects.link(camera)
    scene = bpy.context.scene
    scene.camera = camera
    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.36, 0.62, 0.95, 1.0)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.7
    if render_to:
        scene.render.engine = 'CYCLES'
        scene.cycles.samples, scene.cycles.device = 24, 'CPU'
        scene.render.resolution_x, scene.render.resolution_y = 1280, 720
        scene.view_settings.view_transform = 'Standard'
        scene.render.filepath = render_to
        bpy.ops.render.render(write_still=True)
        print("Rendered %s" % render_to)


def main():
    made = reset_collections()
    world, assets = made["Coast_World"], made["Coast_Assets"]
    terrain, elevations = build_terrain(world)
    tarmac, paint = material("Runway", (0.33, 0.35, 0.38), 0.85), material("RunwayPaint", (0.93, 0.93, 0.88), 0.7)
    for team, centre, heading in AIRFIELDS:
        build_airfield(team, centre, heading, elevations[team], world, tarmac, paint)
        print("Airfield %s at (%.0f, %.0f), %.1f m up: main runway %.0f m (%.0f yd), two of %.0f m (%.0f yd), %.1f m (%.0f yd) wide" % (
            team, centre[0], centre[1], elevations[team], RUNWAY_MAIN, RUNWAY_MAIN / YARD, RUNWAY_SECONDARY, RUNWAY_SECONDARY / YARD,
            RUNWAY_WIDTH, RUNWAY_WIDTH / YARD))
    tree, boulder, cottage = build_tree(assets), build_boulder(assets), build_cottage(assets)
    if EXPORT:
        export_glb([terrain] + [obj for obj in world.objects if obj is not terrain], "coast_terrain.glb")
        export_glb([tree], "coast_tree.glb")
        export_glb([boulder], "coast_boulder.glb")
        export_glb([cottage], "coast_cottage.glb")
    build_preview(made["Coast_Preview"], PREVIEW_IMAGE)


if __name__ == "__main__":
    main()
