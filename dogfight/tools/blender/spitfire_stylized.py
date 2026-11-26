"""
Stylized chunky Spitfire -> Godot 4 (.glb)
==========================================
Procedurally models a toy-like, Supercell-proportioned WWII fighter and exports
it as `spitfire_stylized.glb`, ready to drop into a Godot 4 project.

Run it either way (Blender 4.x):
  * Blender > Scripting workspace > open this file > Run Script
  * blender --background --python spitfire_stylized.py -- /optional/out/path.glb

What you get in the .glb
------------------------
  SpitfireBody   (mesh)  fuselage, wings, tail, wing cannons, exhausts, seat
  ├─ PropellerMesh (mesh)  spinner + 3 blades. Origin = hub centre, so in Godot
  │                        `$SpitfireBody/PropellerMesh.rotate_z(speed * delta)`
  │                        spins it cleanly around its own axle.
  └─ CanopyMesh    (mesh)  bubble canopy, kept separate so the transparent
                           surface sorts correctly and can be swapped/hidden.

Material slots (names survive into Godot as surface material names):
  BodyPrimary, WingAccent_TeamColor, CanopyGlass, MetalDark, PropellerWood
`WingAccent_TeamColor` covers wingtips, tail tips, fin top, fuselage band and
spinner: override that one material in Godot to repaint a plane Red or Blue.

Orientation
-----------
The plane is modelled in Blender's usual "front view" convention (nose toward
-Y, up +Z), then rotated 180 degrees so the nose points along Blender +Y and
all transforms are applied. The glTF exporter converts Blender +Y to glTF -Z,
which is Godot's forward. In Godot: nose = -Z, right wing = +X, up = +Y.

How the mesh is built
---------------------
Every part starts as a deliberately low-poly quad "cage" (lofted rings), gets
a Bevel modifier (angle-limited, so only real creases are rounded) followed by
a Subdivision Surface modifier, and the stack is then applied through the
dependency graph. No bpy.ops are needed for modelling, so the script behaves
the same in the UI and in --background mode.

Budget: about 15k triangles with HERO_SUBDIV = 2, about 9k with HERO_SUBDIV = 1.
"""

from __future__ import annotations

import math
import os
import sys
from typing import Callable, Sequence

import bpy  # Must come first: as a standalone module, bpy is what provides bmesh/mathutils.
import bmesh
from mathutils import Matrix, Vector

# =============================================================================
# Tweakables
# =============================================================================

EXPORT_FILENAME = "spitfire_stylized.glb"
CLEAR_SCENE = True          # Remove everything in the scene before building.
# Subdivision Surface levels. Big, silhouette-defining parts (fuselage, wing)
# get HERO; small parts (tail, blades, cannons, ...) get DETAIL.
#   HERO 2 / DETAIL 1 = close-up asset.   HERO 1 / DETAIL 1 = in-game mobile LOD.
HERO_SUBDIV = 2
DETAIL_SUBDIV = 1
BEVEL_ANGLE_DEG = 40.0      # Edges sharper than this get rounded by the Bevel.

# --- Proportions (metres). Chunky on purpose: short, fat and stubby. ---------
FUSELAGE_SEGMENTS = 12      # Vertices around the fuselage cage.
# Fuselage stations from nose to tail: (y, half_width, half_height, z_centre).
FUSELAGE_STATIONS = [
    (-2.40, 0.62, 0.62, 0.00),   # Nose ring: matches the spinner's base.
    (-2.10, 0.84, 0.86, 0.00),
    (-1.40, 0.97, 1.02, 0.00),
    (-0.40, 1.00, 1.10, 0.02),   # Fattest point, just ahead of the cockpit.
    (0.60, 0.90, 1.00, 0.06),
    (1.50, 0.64, 0.76, 0.14),
    (2.20, 0.38, 0.48, 0.22),
    (2.70, 0.17, 0.24, 0.28),    # Tail cone tip.
]
TEAM_BAND_Y = (1.50, 2.20)   # Fuselage section painted in the team colour.

WING_SPAN = 7.2
WING_ROOT_CHORD = 2.35
WING_THICKNESS = 0.42
WING_DIHEDRAL_DEG = 6.0
WING_CENTRE = Vector((0.0, -0.45, -0.42))   # Low-wing monoplane.
WING_TIP_ACCENT = 0.70       # Outer 30% of each wing is team colour.

TAILPLANE_SPAN = 3.1
TAILPLANE_ROOT_CHORD = 1.15
TAILPLANE_THICKNESS = 0.24
TAILPLANE_CENTRE = Vector((0.0, 2.18, 0.30))

FIN_HEIGHT = 1.45
FIN_ROOT_CHORD = 1.35
FIN_THICKNESS = 0.24
FIN_BASE = Vector((0.0, 2.12, 0.35))

SPINNER_RADIUS = 0.62        # Oversized nose cone.
SPINNER_LENGTH = 1.00
PROP_RADIUS = 1.85           # Oversized propeller.
PROP_BLADES = 3
PROP_HUB = Vector((0.0, -2.72, 0.0))   # Propeller pivot (hub centre).

CANOPY_CENTRE = Vector((0.0, -0.10, 0.98))
CANOPY_RADII = Vector((0.56, 1.02, 0.58))

CANNON_SPAN_FRACTIONS = (0.40,)   # One chunky cannon per wing; add 0.55 for two.
CANNON_RADIUS = 0.17
CANNON_LENGTH = 1.05

# --- Materials: (sRGB hex, alpha, metallic, roughness) -----------------------
MATERIAL_SPECS = {
    "BodyPrimary": ("4FB548", 1.0, 0.0, 0.55),            # Vibrant toy green.
    "WingAccent_TeamColor": ("1E78FF", 1.0, 0.0, 0.45),   # Team paint (blue).
    "CanopyGlass": ("9FE3FF", 0.38, 0.0, 0.08),           # Glossy, see-through.
    "MetalDark": ("2A2E36", 1.0, 0.85, 0.40),             # Gunmetal.
    "PropellerWood": ("B5713A", 1.0, 0.0, 0.70),          # Warm varnished wood.
}
# Slot order is identical on every part, so face material indices stay valid
# when parts are merged.
MATERIAL_ORDER = list(MATERIAL_SPECS.keys())
BODY, ACCENT, GLASS, METAL, WOOD = range(5)

Ring = Sequence[Vector]
FacePainter = Callable[[Vector], int]


# =============================================================================
# Scene + materials
# =============================================================================

def clear_scene() -> None:
    """Deletes every object, then any mesh/material left without users."""
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)
    for material in list(bpy.data.materials):
        if material.users == 0:
            bpy.data.materials.remove(material)


def srgb_hex_to_linear(hex_color: str) -> tuple[float, float, float]:
    """Blender (and glTF) store base colours in linear space."""
    def channel(value: int) -> float:
        srgb = value / 255.0
        return srgb / 12.92 if srgb <= 0.04045 else ((srgb + 0.055) / 1.055) ** 2.4
    return tuple(channel(int(hex_color[i:i + 2], 16)) for i in (0, 2, 4))


def build_materials() -> list[bpy.types.Material]:
    """Principled BSDF materials using only inputs the glTF exporter maps 1:1
    onto Godot's StandardMaterial3D (base colour, alpha, metallic, roughness)."""
    materials = []
    for name in MATERIAL_ORDER:
        hex_color, alpha, metallic, roughness = MATERIAL_SPECS[name]
        material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        material.use_nodes = True
        # Looked up by type, not name: node names are translated in some locales.
        bsdf = next(node for node in material.node_tree.nodes if node.type == 'BSDF_PRINCIPLED')
        red, green, blue = srgb_hex_to_linear(hex_color)
        bsdf.inputs["Base Color"].default_value = (red, green, blue, 1.0)
        bsdf.inputs["Alpha"].default_value = alpha
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
        material.diffuse_color = (red, green, blue, alpha)   # Solid-view colour.
        # Exported as glTF doubleSided = false -> Godot culls back faces
        # (cheaper on mobile, and the closed meshes never show their insides).
        material.use_backface_culling = True
        if alpha < 1.0:
            # Exported as glTF alphaMode BLEND -> Godot "Alpha" transparency.
            if hasattr(material, "surface_render_method"):
                material.surface_render_method = 'BLENDED'    # Blender 4.2+
            else:
                material.blend_mode = 'BLEND'                 # Blender 4.0 / 4.1
        materials.append(material)
    return materials


# =============================================================================
# Low-poly cage helpers (bmesh, all quads apart from small end caps)
# =============================================================================

def loft_rings(bm: bmesh.types.BMesh, rings: Sequence[Ring], cap_start: bool = True, cap_end: bool = True) -> None:
    """Skins consecutive rings (same vertex count each) with quads.
    End caps are single n-gons; the Bevel modifier rounds their rims and the
    Subdivision Surface turns them into clean quad fans."""
    vertex_rings = [[bm.verts.new(point) for point in ring] for ring in rings]
    count = len(vertex_rings[0])
    for lower, upper in zip(vertex_rings, vertex_rings[1:]):
        for index in range(count):
            following = (index + 1) % count
            bm.faces.new((lower[index], lower[following], upper[following], upper[index]))
    if cap_start:
        bm.faces.new(vertex_rings[0])
    if cap_end:
        bm.faces.new(vertex_rings[-1])


def ellipse_ring(centre: Vector, axis_u: Vector, axis_v: Vector, radius_u: float, radius_v: float, segments: int,
                 phase: float = 0.0) -> list[Vector]:
    """Points on an ellipse spanned by two axes."""
    return [
        centre + axis_u * (radius_u * math.cos(phase + math.tau * index / segments))
        + axis_v * (radius_v * math.sin(phase + math.tau * index / segments))
        for index in range(segments)
    ]


def lathe_y(bm: bmesh.types.BMesh, profile: Sequence[tuple[float, float]], segments: int) -> None:
    """Revolves a (y, radius) profile around the Y axis."""
    rings = [ellipse_ring(Vector((0.0, y, 0.0)), Vector((1, 0, 0)), Vector((0, 0, 1)), radius, radius, segments)
             for y, radius in profile]
    loft_rings(bm, rings)


def lifting_surface(bm: bmesh.types.BMesh, half_span: float, root_chord: float, thickness: float,
                    dihedral_deg: float = 0.0, both_sides: bool = True, loop_points: int = 8) -> None:
    """Wing-like slab in local space: span along X, chord along Y (leading edge
    toward -Y), thickness along Z. The planform is an ellipse, like the real
    Spitfire wing, but far stubbier, and the section is a fat rounded oval."""
    fractions = [0.0, 0.30, 0.58, 0.80, 0.93, 0.985]
    stations = fractions if not both_sides else [-f for f in reversed(fractions[1:])] + fractions
    rise = math.tan(math.radians(dihedral_deg))
    rings = []
    for fraction in stations:
        taper = math.sqrt(max(1.0 - fraction * fraction, 0.0))
        chord = root_chord * taper
        # Thickness shrinks slower than chord so the tips stay chunky.
        depth = thickness * taper ** 0.6
        # Slide outer sections forward so the leading edge stays straighter
        # than the trailing edge (the classic elliptical-wing look).
        centre = Vector((fraction * half_span, -0.14 * (root_chord - chord), abs(fraction) * half_span * rise))
        rings.append(ellipse_ring(centre, Vector((0, 1, 0)), Vector((0, 0, 1)), chord * 0.5, depth * 0.5, loop_points))
    loft_rings(bm, rings)


def paint(bm: bmesh.types.BMesh, painter: FacePainter) -> None:
    """Assigns a material slot to every face from its centre position."""
    for face in bm.faces:
        face.material_index = painter(face.calc_center_median())


# =============================================================================
# Cage -> finished mesh (Bevel + Subdivision Surface, applied)
# =============================================================================

def finish_part(name: str, bm: bmesh.types.BMesh, materials: Sequence[bpy.types.Material],
                bevel_width: float = 0.0, bevel_segments: int = 1,
                subdiv_levels: int = DETAIL_SUBDIV) -> bpy.types.Mesh:
    """Turns a cage into final geometry: fixes normals, adds the modifier stack
    (Bevel first so it holds the creases, then Subdivision Surface), applies it
    through the dependency graph and returns the resulting mesh datablock."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    # recalc_face_normals makes normals consistent; a negative signed volume
    # would mean "consistently inside-out", so flip in that case.
    if bm.calc_volume(signed=True) < 0.0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    cage = bpy.data.meshes.new(f"{name}_cage")
    bm.to_mesh(cage)
    bm.free()
    for material in materials:
        cage.materials.append(material)

    temp = bpy.data.objects.new(f"{name}_tmp", cage)
    bpy.context.scene.collection.objects.link(temp)
    if bevel_width > 0.0:
        bevel = temp.modifiers.new("Bevel", 'BEVEL')
        bevel.width = bevel_width
        bevel.segments = bevel_segments
        bevel.limit_method = 'ANGLE'
        bevel.angle_limit = math.radians(BEVEL_ANGLE_DEG)
        bevel.use_clamp_overlap = True      # Never let bevels cross each other.
    if subdiv_levels > 0:
        subsurf = temp.modifiers.new("Subdivision", 'SUBSURF')
        subsurf.subdivision_type = 'CATMULL_CLARK'
        subsurf.levels = subdiv_levels
        subsurf.render_levels = subdiv_levels

    # "Apply" the stack: evaluate the object and copy out the result.
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    result = bpy.data.meshes.new_from_object(temp.evaluated_get(depsgraph))
    result.name = name
    print(f"    part {name:<10} cage {len(cage.polygons):>4} faces -> {triangle_count(result):>5} tris")
    bpy.data.objects.remove(temp, do_unlink=True)
    bpy.data.meshes.remove(cage)
    return result


def merge_meshes(name: str, parts: Sequence[bpy.types.Mesh], materials: Sequence[bpy.types.Material],
                 offset: Vector = Vector((0.0, 0.0, 0.0))) -> bpy.types.Mesh:
    """Joins finished parts into one mesh, shifted by [offset] (used to put the
    propeller's geometry around its own origin). Source parts are deleted."""
    bm = bmesh.new()
    for part in parts:
        bm.from_mesh(part)
    if offset.length > 0.0:
        bmesh.ops.translate(bm, verts=bm.verts[:], vec=offset)
    for face in bm.faces:
        face.smooth = True
    merged = bpy.data.meshes.new(name)
    bm.to_mesh(merged)
    bm.free()
    for material in materials:
        merged.materials.append(material)
    for part in parts:
        bpy.data.meshes.remove(part)
    remove_unused_material_slots(merged)
    return merged


def remove_unused_material_slots(mesh: bpy.types.Mesh) -> None:
    """Keeps only the material slots that faces actually use."""
    old_indices = [polygon.material_index for polygon in mesh.polygons]
    used = sorted(set(old_indices))
    remap = {old: new for new, old in enumerate(used)}
    kept = [mesh.materials[index] for index in used]
    # Order matters: clearing the slot list resets every face to slot 0, so the
    # remapped indices are written back only after the slots are rebuilt.
    mesh.materials.clear()
    for material in kept:
        mesh.materials.append(material)
    mesh.polygons.foreach_set("material_index", [remap[index] for index in old_indices])
    mesh.update()


# =============================================================================
# Parts. Everything is modelled nose-toward -Y, up +Z.
# =============================================================================

def wing_surface_point(span_fraction: float, chord_fraction: float) -> Vector:
    """World-space point on the wing's mid-surface. chord_fraction: 0 = leading
    edge, 1 = trailing edge. Used to mount things (cannons) on the wing."""
    half_span = WING_SPAN * 0.5
    chord = WING_ROOT_CHORD * math.sqrt(max(1.0 - span_fraction * span_fraction, 0.0))
    centre_y = -0.14 * (WING_ROOT_CHORD - chord)
    local = Vector((
        span_fraction * half_span,
        centre_y - chord * 0.5 + chord * chord_fraction,
        abs(span_fraction) * half_span * math.tan(math.radians(WING_DIHEDRAL_DEG)),
    ))
    return WING_CENTRE + local


def make_fuselage(materials) -> bpy.types.Mesh:
    bm = bmesh.new()
    rings = [
        # Phase offset puts an edge, not a vertex, on the top centre line.
        ellipse_ring(Vector((0.0, y, z)), Vector((1, 0, 0)), Vector((0, 0, 1)), half_width, half_height,
                     FUSELAGE_SEGMENTS, math.pi / FUSELAGE_SEGMENTS)
        for y, half_width, half_height, z in FUSELAGE_STATIONS
    ]
    loft_rings(bm, rings)
    band_start, band_end = TEAM_BAND_Y
    paint(bm, lambda centre: ACCENT if band_start < centre.y < band_end else BODY)
    return finish_part("Fuselage", bm, materials, bevel_width=0.06, subdiv_levels=HERO_SUBDIV)


def make_wing(materials) -> bpy.types.Mesh:
    bm = bmesh.new()
    lifting_surface(bm, WING_SPAN * 0.5, WING_ROOT_CHORD, WING_THICKNESS, WING_DIHEDRAL_DEG)
    bmesh.ops.translate(bm, verts=bm.verts[:], vec=WING_CENTRE)
    tip_start = WING_SPAN * 0.5 * WING_TIP_ACCENT
    paint(bm, lambda centre: ACCENT if abs(centre.x) > tip_start else BODY)
    return finish_part("Wing", bm, materials, bevel_width=0.04, subdiv_levels=HERO_SUBDIV)


def make_tailplane(materials) -> bpy.types.Mesh:
    bm = bmesh.new()
    lifting_surface(bm, TAILPLANE_SPAN * 0.5, TAILPLANE_ROOT_CHORD, TAILPLANE_THICKNESS)
    bmesh.ops.translate(bm, verts=bm.verts[:], vec=TAILPLANE_CENTRE)
    tip_start = TAILPLANE_SPAN * 0.5 * 0.62
    paint(bm, lambda centre: ACCENT if abs(centre.x) > tip_start else BODY)
    return finish_part("Tailplane", bm, materials, bevel_width=0.03)


def make_fin(materials) -> bpy.types.Mesh:
    bm = bmesh.new()
    lifting_surface(bm, FIN_HEIGHT, FIN_ROOT_CHORD, FIN_THICKNESS, both_sides=False)
    # Stand the half-wing up: local span (+X) becomes world +Z.
    bmesh.ops.transform(bm, verts=bm.verts[:], matrix=Matrix.Rotation(-math.pi / 2.0, 4, 'Y'))
    bmesh.ops.translate(bm, verts=bm.verts[:], vec=FIN_BASE)
    accent_from = FIN_BASE.z + FIN_HEIGHT * 0.45
    paint(bm, lambda centre: ACCENT if centre.z > accent_from else BODY)
    return finish_part("Fin", bm, materials, bevel_width=0.03)


def make_cannon(materials, side: float, span_fraction: float) -> bpy.types.Mesh:
    """Fat barrel with a flared muzzle brake and a recessed bore, sunk into
    the wing's leading edge."""
    radius = CANNON_RADIUS
    profile = [
        (0.45, radius * 0.90),                     # Buried inside the wing.
        (-CANNON_LENGTH * 0.62, radius * 0.90),    # Barrel.
        (-CANNON_LENGTH * 0.62, radius * 1.45),    # Step up to the muzzle brake.
        (-CANNON_LENGTH, radius * 1.45),
        (-CANNON_LENGTH + 0.14, radius * 0.70),    # Dished muzzle with a bore.
    ]
    bm = bmesh.new()
    lathe_y(bm, profile, 8)
    mount = wing_surface_point(side * span_fraction, 0.12)
    bmesh.ops.translate(bm, verts=bm.verts[:], vec=mount)
    paint(bm, lambda _centre: METAL)
    return finish_part("Cannon", bm, materials, bevel_width=0.025)


def make_exhaust(materials, side: float, index: int) -> bpy.types.Mesh:
    """Stubby exhaust pipe on the cowling, swept back and outward."""
    bm = bmesh.new()
    lathe_y(bm, [(0.0, 0.085), (0.34, 0.10), (0.30, 0.055)], 6)
    # The pipe is built pointing aft (+Y here); swing it outward on its side.
    sweep = Matrix.Rotation(-side * math.radians(62.0), 4, 'Z')
    bmesh.ops.transform(bm, verts=bm.verts[:], matrix=sweep)
    bmesh.ops.translate(bm, verts=bm.verts[:], vec=Vector((side * 0.84, -1.92 + index * 0.30, 0.34)))
    paint(bm, lambda _centre: METAL)
    # Too small for a bevel to read: Subdivision Surface alone rounds it off.
    return finish_part("Exhaust", bm, materials)


def make_headrest(materials) -> bpy.types.Mesh:
    """A seat back under the glass, so the bubble canopy is not empty."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, verts=bm.verts[:], vec=Vector((0.58, 0.20, 0.70)))
    bmesh.ops.translate(bm, verts=bm.verts[:], vec=CANOPY_CENTRE + Vector((0.0, 0.40, 0.06)))
    paint(bm, lambda _centre: METAL)
    return finish_part("Headrest", bm, materials, bevel_width=0.05)


def make_canopy(materials) -> bpy.types.Mesh:
    """Bubble canopy: a stretched sphere whose lower half hides in the fuselage."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=6, radius=1.0)
    bmesh.ops.scale(bm, verts=bm.verts[:], vec=CANOPY_RADII)
    paint(bm, lambda _centre: GLASS)
    # Built around the origin: the object is placed at CANOPY_CENTRE instead.
    return finish_part("Canopy", bm, materials)


def make_spinner(materials) -> bpy.types.Mesh:
    """Oversized bullet nose cone in prop-local space (hub at the origin)."""
    steps = 5
    profile = [(0.30, SPINNER_RADIUS * 0.96), (0.26, SPINNER_RADIUS)]
    for step in range(1, steps + 1):
        t = step / steps
        # Half-ellipse: blunt and round rather than pointy.
        profile.append((0.26 - (SPINNER_LENGTH - 0.04) * t, SPINNER_RADIUS * math.sqrt(max(1.0 - t * t, 0.0)) + 0.03 * (1.0 - t)))
    bm = bmesh.new()
    lathe_y(bm, profile, 10)
    paint(bm, lambda _centre: ACCENT)
    return finish_part("Spinner", bm, materials, bevel_width=0.03)


def make_blade(materials, angle: float) -> bpy.types.Mesh:
    """One fat paddle blade in prop-local space, twisted from root to tip."""
    # (distance from hub, half width, half thickness, pitch in degrees)
    sections = [
        (0.30, 0.13, 0.11, 55.0),
        (0.65, 0.25, 0.085, 42.0),
        (1.05, 0.31, 0.065, 30.0),
        (1.45, 0.29, 0.05, 22.0),
        (PROP_RADIUS - 0.10, 0.20, 0.04, 17.0),
        (PROP_RADIUS, 0.10, 0.03, 15.0),
    ]
    rings = []
    for distance, half_width, half_thickness, pitch_deg in sections:
        pitch = Matrix.Rotation(math.radians(pitch_deg), 3, 'Z')
        rings.append(ellipse_ring(Vector((0.0, 0.0, distance)), pitch @ Vector((1, 0, 0)), pitch @ Vector((0, 1, 0)),
                                  half_width, half_thickness, 8))
    bm = bmesh.new()
    loft_rings(bm, rings)
    bmesh.ops.transform(bm, verts=bm.verts[:], matrix=Matrix.Rotation(angle, 4, 'Y'))
    paint(bm, lambda _centre: WOOD)
    return finish_part("Blade", bm, materials, bevel_width=0.015)


# =============================================================================
# Assembly, orientation, export
# =============================================================================

def new_object(name: str, mesh: bpy.types.Mesh, location: Vector = Vector((0.0, 0.0, 0.0))) -> bpy.types.Object:
    mesh.name = name
    obj = bpy.data.objects.new(name, mesh)
    obj.location = location
    bpy.context.scene.collection.objects.link(obj)
    return obj


def orient_for_godot(objects: Sequence[bpy.types.Object]) -> None:
    """Turns the model to face Blender +Y (= Godot -Z after glTF export) and
    applies all transforms.

    Same result as rotating 180 degrees on Z and pressing Ctrl+A > All
    Transforms on the body: rotation becomes (0, 0, 0) and scale (1, 1, 1) on
    every object, with the body's origin at the world origin. The propeller and
    canopy deliberately keep a *location* (their origin stays on the hub /
    bubble centre) because that origin is the pivot Godot will spin around."""
    turn = Matrix.Rotation(math.pi, 4, 'Z')
    bpy.context.view_layer.update()
    for obj in objects:
        world = turn @ obj.matrix_world
        pivot = world.to_translation()
        # Bake everything except the pivot offset into the vertices.
        obj.data.transform(Matrix.Translation(-pivot) @ world)
        obj.matrix_world = Matrix.Translation(pivot)
        obj.data.update()
    bpy.context.view_layer.update()


def resolve_export_path() -> str:
    """Optional path after `--` on the command line; otherwise next to the
    .blend, next to this script, or the home folder, in that order."""
    if "--" in sys.argv:
        extra = sys.argv[sys.argv.index("--") + 1:]
        if extra:
            return os.path.abspath(extra[0])
    if bpy.data.filepath:
        return os.path.join(os.path.dirname(bpy.data.filepath), EXPORT_FILENAME)
    script_path = globals().get("__file__", "")
    if script_path and os.path.isfile(script_path):
        return os.path.join(os.path.dirname(os.path.abspath(script_path)), EXPORT_FILENAME)
    return os.path.join(os.path.expanduser("~"), EXPORT_FILENAME)


def triangle_count(mesh: bpy.types.Mesh) -> int:
    return sum(len(polygon.vertices) - 2 for polygon in mesh.polygons)


def build_plane() -> list[bpy.types.Object]:
    if CLEAR_SCENE:
        clear_scene()
    materials = build_materials()

    # --- Body: one mesh, several material surfaces ---------------------------
    body_parts = [make_fuselage(materials), make_wing(materials), make_tailplane(materials),
                  make_fin(materials), make_headrest(materials)]
    for side in (-1.0, 1.0):
        for span_fraction in CANNON_SPAN_FRACTIONS:
            body_parts.append(make_cannon(materials, side, span_fraction))
        for index in range(3):
            body_parts.append(make_exhaust(materials, side, index))
    body = new_object("SpitfireBody", merge_meshes("SpitfireBody", body_parts, materials))

    # --- Propeller: built around its own origin, then placed on the nose -----
    prop_parts = [make_spinner(materials)]
    prop_parts += [make_blade(materials, math.tau * blade / PROP_BLADES) for blade in range(PROP_BLADES)]
    propeller = new_object("PropellerMesh", merge_meshes("PropellerMesh", prop_parts, materials), PROP_HUB)

    # --- Canopy --------------------------------------------------------------
    canopy = new_object("CanopyMesh", merge_meshes("CanopyMesh", [make_canopy(materials)], materials), CANOPY_CENTRE)

    objects = [body, propeller, canopy]
    orient_for_godot(objects)

    # Parent after orienting: the body sits at the origin with an identity
    # transform, so each child's local transform equals its world transform.
    for child in (propeller, canopy):
        child.parent = body
        child.matrix_parent_inverse = Matrix.Identity(4)

    # Sanity checks: nose toward Blender +Y, propeller geometry centred on its axle.
    assert propeller.location.y > 0.0, "nose must point along Blender +Y (Godot -Z)"
    for obj in objects:
        assert tuple(round(value, 6) for value in obj.rotation_euler) == (0.0, 0.0, 0.0), f"{obj.name}: rotation not applied"
        assert tuple(round(value, 6) for value in obj.scale) == (1.0, 1.0, 1.0), f"{obj.name}: scale not applied"
    axle_error = max(abs(sum(v.co.x for v in propeller.data.vertices)), abs(sum(v.co.z for v in propeller.data.vertices))) / len(propeller.data.vertices)
    assert axle_error < 1e-3, "propeller is not centred on its pivot"

    total = 0
    for obj in objects:
        triangles = triangle_count(obj.data)
        total += triangles
        slots = ", ".join(material.name for material in obj.data.materials)
        print(f"  {obj.name:<14} {len(obj.data.vertices):>6} verts {triangles:>6} tris   location {tuple(round(c, 3) for c in obj.location)}   [{slots}]")
    print(f"  total {total} tris at HERO_SUBDIV={HERO_SUBDIV}, DETAIL_SUBDIV={DETAIL_SUBDIV}")
    return objects


def export_glb(objects: Sequence[bpy.types.Object], filepath: str) -> None:
    os.makedirs(os.path.dirname(filepath) or ".", exist_ok=True)
    for obj in bpy.context.scene.objects:
        obj.select_set(False)
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format='GLB',
        use_selection=True,
        export_apply=True,       # Nothing left to apply; kept as a safety net.
        export_yup=True,         # Blender +Y (nose) -> glTF/Godot -Z, Blender +Z -> +Y.
        export_materials='EXPORT',
        export_normals=True,
        export_texcoords=False,  # Flat colours only: no UVs needed.
        export_animations=False,
        export_cameras=False,
        export_lights=False,
    )
    print(f"Exported {filepath}")


if __name__ == "__main__":
    plane_objects = build_plane()
    export_glb(plane_objects, resolve_export_path())  # -> spitfire_stylized.glb
