"""
Three WWII fighters to real dimensions, built to break apart -> Godot 4 (.glb)
==============================================================================
Procedurally models the Hawker Hurricane Mk II, the Supermarine Spitfire Mk V
and the North American P-51D Mustang, each to its published dimensions
(span, length, wing area and planform, tailplane span, propeller diameter,
undercarriage track, how high it stands and at what angle), each as a set of
separate pieces that the game can damage, hinge and shoot off, and exports
`hurricane.glb`, `spitfire.glb` and `mustang.glb`.

Run it either way (Blender 4.x):
  * Blender > Scripting workspace > open this file > Run Script
  * blender --background --python warbirds.py -- [output folder] [hero=1]

Each aeroplane is a table of numbers in SPECS, in metres. The model's origin
is the aeroplane's centre of gravity, so where the wheels are in the model is
where they are relative to the weight: that is what the game's ground
handling is worked out from. The shapes are simple (oval sections, plain
planforms) and coloured in the game's flat team scheme; the sizes and
proportions are the real ones.

Pieces and hierarchy (every name below is a mesh node in each .glb)
-------------------------------------------------------------------
  Fuselage                  centre section, pilot, wing root; the root node
  ├─ Engine                 nose and cowling, exhaust stubs
  │  └─ PropellerMesh       spinner + blades, origin on the hub: spin around Z
  ├─ CanopyMesh             canopy (transparent)
  ├─ WingL / WingR          inner wing panel
  │  ├─ GunL1_303 ...       one gun per station (L1 R1 inner, L2 R2 outer) and
  │  │                      per type (303, 50, 20): the game shows only the
  │  │                      ones that are fitted. Origin on the leading edge.
  │  ├─ FlapL / FlapR       hinged: rotate around local X
  │  ├─ GearL / GearR       undercarriage leg, wheel and door, origin on the
  │  │                      pivot: rotate around local Y to retract (outward
  │  │                      on the Spitfire, inward on the other two)
  │  └─ WingTipL / WingTipR outer wing panel
  │     └─ AileronL / AileronR   hinged: rotate around local X
  └─ Tail                   rear fuselage
     ├─ StabiliserL / StabiliserR
     ├─ ElevatorL / ElevatorR     hinged: rotate around local X
     ├─ TailWheel                 tail wheel and strut
     └─ Fin
        └─ Rudder                 hinged: rotate around local Y

Alternative fittings (the game shows or swaps these to match the loadout):
  PropellerMesh4            four-blade propeller, in place of PropellerMesh
  EngineIntake, EngineBulges   chin intake and cowl blisters of bigger engines
  ArmourSeat, ArmourScreen  armour plate behind the seat / armoured windscreen
  WingTipL_clipped / R      squared-off outer panel: its mesh replaces WingTip's
  WingTipExtL / R           pointed extension added beyond the standard tip
  GearL_heavy / R           reinforced leg and wheel: its mesh replaces Gear's

Because children follow their parent, detaching `WingL` in the engine takes
its flap, tip and aileron with it; detaching `Tail` takes the whole empennage.

How the pieces are made
-----------------------
The fuselage, wing, tailplane and fin are each modelled whole (low-poly quad
cage -> Bevel -> Subdivision Surface, applied). They are then *cut* into
pieces with exact booleans:
  * every control surface is the part of the wing/tail/fin that lies behind
    its hinge line, so it has exactly the section it was cut from, and the
    parent keeps a matching notch with a small gap;
  * panels are separated along break lines (wing root, mid-span, firewall,
    tail joint). Cut faces get the dark metal material, so a broken-off piece
    shows structure instead of a hole.

Hinged pieces keep a rotation: their local X axis (local Y for the rudder)
lies along the hinge line, with the origin on it, so in Godot
`node.basis = rest_basis * Basis(Vector3.RIGHT, angle)` swings the surface
(positive = trailing edge down; for the rudder, positive Y = trailing edge to
the right). Every other piece has only a translation.

Orientation
-----------
Parts are modelled in Blender's "front view" convention (nose toward -Y),
then turned 180 degrees so the nose points along Blender +Y. The glTF
exporter maps Blender +Y to -Z, Godot's forward. In Godot: nose = -Z,
right wing = +X, up = +Y.

Material slots (names survive into Godot as surface material names):
  BodyPrimary, WingAccent_TeamColor, CanopyGlass, MetalDark, PropellerWood,
  PilotSkin, PilotLeather
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

CLEAR_SCENE = True          # Remove everything in the scene before building.

# Subdivision Surface levels: 2 for the big hero shapes keeps the silhouette
# round; small parts get 1. Lower both to 1 for a lighter in-game mesh.
HERO_SUBDIV = 2
DETAIL_SUBDIV = 1
BEVEL_ANGLE_DEG = 40.0      # Edges sharper than this get rounded by the Bevel.
SHARP_ANGLE_DEG = 50.0      # After cutting, edges sharper than this stay crisp.
SURFACE_GAP = 0.025         # Visible gap around every control surface (metres).
FUSELAGE_SEGMENTS = 12      # Vertices around the fuselage cage.
WING_CLIP_FRACTION = 0.91     # Clipped wings end here (fraction of half span).
WING_EXTENSION = (0.955, 1.06, 1.15)   # Root, middle and point of an extended tip.
HEAVY_GEAR_SCALE = 1.18       # Reinforced undercarriage: this much bigger.
GEAR_LEG_RADIUS = 0.05
PILOT_SCALE = 0.5             # The pilot's head is 26 cm across.

# Gun types: lathe profile as (distance ahead of the leading edge, radius).
# Negative = sticking out forward. All start buried inside the wing.
GUN_PROFILES = {
    "303": [(0.25, 0.035), (-0.10, 0.035), (-0.10, 0.022), (-0.22, 0.022), (-0.20, 0.012)],
    "50": [(0.25, 0.045), (-0.18, 0.045), (-0.18, 0.030), (-0.45, 0.030), (-0.43, 0.015)],
    "20": [(0.35, 0.060), (-0.45, 0.060), (-0.45, 0.040), (-1.00, 0.040), (-0.97, 0.020)],
}

# --- The aeroplanes ----------------------------------------------------------
# Everything is in metres, in *build space*: nose toward -Y, up +Z, and the
# origin at the centre of gravity. So a station's y is how far behind (+) or
# ahead (-) of the centre of gravity it is.
#
# FUSELAGE_STATIONS, nose to tail: (y, half_width, half_height, z_centre).
# A PLANFORM is ("ellipse", sweep) or ("taper", sweep, flat_to, tip_ratio,
# round_from): the chord stays at the root's out to flat_to of the half span,
# tapers to tip_ratio of it at the tip, and is rounded off from round_from on
# (1.0 = a square tip). `sweep` is how far forward the middle of each chord
# moves as the chord shortens: 0.25 keeps the quarter-chord line straight.
# FAIRINGS are extra lumps (radiators, scoops) lofted and joined to a piece:
# (piece, [(y, x_centre, z_centre, half_width, half_height), ...]).
SPECS = {
    # Supermarine Spitfire Mk Vb. Span 36 ft 10 in, length 29 ft 11 in,
    # wing area 242 sq ft (an ellipse), track 5 ft 8.5 in, propeller 10 ft 9 in.
    "spitfire": dict(
        FUSELAGE_STATIONS=[(-2.07, 0.33, 0.33, 0.10), (-1.75, 0.40, 0.44, 0.08), (-1.00, 0.43, 0.52, 0.04),
                           (-0.30, 0.45, 0.58, 0.02), (0.80, 0.45, 0.62, 0.02), (2.00, 0.38, 0.52, 0.10),
                           (3.50, 0.25, 0.36, 0.20), (5.00, 0.12, 0.22, 0.30), (5.95, 0.04, 0.10, 0.36)],
        TEAM_BAND_Y=(3.30, 3.90),
        WING_SPAN=11.23, WING_ROOT_CHORD=2.54, WING_THICKNESS=0.33, WING_DIHEDRAL_DEG=6.0,
        WING_CENTRE=Vector((0.0, 0.55, -0.42)), WING_PLANFORM=("ellipse", 0.25), WING_TIP_ACCENT=0.80,
        TAILPLANE_SPAN=3.20, TAILPLANE_ROOT_CHORD=1.25, TAILPLANE_THICKNESS=0.14,
        TAILPLANE_CENTRE=Vector((0.0, 5.25, 0.40)), TAILPLANE_PLANFORM=("ellipse", 0.10),
        FIN_HEIGHT=1.25, FIN_ROOT_CHORD=1.55, FIN_THICKNESS=0.13, FIN_BASE=Vector((0.0, 5.66, 0.38)),
        FIN_PLANFORM=("ellipse", 0.0),
        SPINNER_RADIUS=0.33, SPINNER_LENGTH=0.65, PROP_RADIUS=1.635, PROP_BLADES=3, PROP_HUB=Vector((0.0, -2.37, 0.10)),
        CANOPY_CENTRE=Vector((0.0, 1.05, 0.62)), CANOPY_RADII=Vector((0.33, 0.85, 0.42)),
        GUN_STATIONS=(("1", 0.34), ("2", 0.52)),
        GEAR_TRACK_X=0.50, GEAR_PIVOT_Y=-0.55, GEAR_AXLE=Vector((0.0, -0.75, -1.48)), GEAR_WHEEL_X=0.865,
        GEAR_WHEEL_RADIUS=0.30, GEAR_WHEEL_WIDTH=0.16, GEAR_FOLDS="out",
        TAIL_WHEEL_CENTRE=Vector((0.0, 5.28, -0.37)), TAIL_WHEEL_RADIUS=0.13, TAIL_WHEEL_WIDTH=0.09,
        TAIL_STRUT_TOP=Vector((0.0, 5.15, 0.05)),
        WING_ROOT_X=0.45, WING_BREAK_FRACTION=0.60, FIREWALL_Y=-0.45, TAIL_JOINT_Y=3.00, STABILISER_ROOT_X=0.10,
        FLAP_SPAN=(0.14, 0.565), FLAP_CHORD=0.22, AILERON_SPAN=(0.635, 0.93), AILERON_CHORD=0.25,
        ELEVATOR_SPAN=(0.12, 0.95), ELEVATOR_CHORD=0.42, RUDDER_SPAN=(0.04, 0.94), RUDDER_CHORD=0.45,
        EXHAUST=(0.41, -1.75, 0.26, 0.22),
        # Radiator under the right wing, oil cooler under the left (build -X is the right wing).
        FAIRINGS=[("WingR", [(0.28, -1.25, -0.52, 0.16, 0.04), (0.45, -1.25, -0.64, 0.30, 0.17),
                             (1.35, -1.25, -0.63, 0.30, 0.16), (1.58, -1.25, -0.52, 0.18, 0.04)]),
                  ("WingL", [(0.40, 1.25, -0.52, 0.08, 0.03), (0.52, 1.25, -0.58, 0.14, 0.10),
                             (1.05, 1.25, -0.58, 0.14, 0.09), (1.20, 1.25, -0.52, 0.08, 0.03)])],
    ),
    # Hawker Hurricane Mk IIc. Span 40 ft, length 32 ft 3 in, wing area
    # 257.5 sq ft, track 7 ft 10 in, propeller 11 ft 3 in. A deep, humped
    # fuselage, a thick wing and a wide, inward-folding undercarriage.
    "hurricane": dict(
        FUSELAGE_STATIONS=[(-2.20, 0.36, 0.36, 0.12), (-1.85, 0.42, 0.50, 0.06), (-1.00, 0.46, 0.60, 0.02),
                           (-0.30, 0.50, 0.68, 0.02), (1.00, 0.50, 0.74, 0.06), (2.20, 0.42, 0.66, 0.14),
                           (4.00, 0.27, 0.46, 0.24), (5.60, 0.12, 0.28, 0.34), (6.45, 0.04, 0.12, 0.40)],
        TEAM_BAND_Y=(3.60, 4.30),
        WING_SPAN=12.19, WING_ROOT_CHORD=2.46, WING_THICKNESS=0.44, WING_DIHEDRAL_DEG=3.5,
        WING_CENTRE=Vector((0.0, 0.58, -0.50)), WING_PLANFORM=("taper", 0.15, 0.22, 0.50, 0.90), WING_TIP_ACCENT=0.80,
        TAILPLANE_SPAN=3.35, TAILPLANE_ROOT_CHORD=1.30, TAILPLANE_THICKNESS=0.15,
        TAILPLANE_CENTRE=Vector((0.0, 5.65, 0.50)), TAILPLANE_PLANFORM=("taper", 0.10, 0.0, 0.60, 0.75),
        FIN_HEIGHT=1.45, FIN_ROOT_CHORD=1.60, FIN_THICKNESS=0.14, FIN_BASE=Vector((0.0, 6.18, 0.42)),
        FIN_PLANFORM=("taper", 0.0, 0.0, 0.50, 0.55),
        SPINNER_RADIUS=0.36, SPINNER_LENGTH=0.70, PROP_RADIUS=1.715, PROP_BLADES=3, PROP_HUB=Vector((0.0, -2.50, 0.12)),
        CANOPY_CENTRE=Vector((0.0, 1.00, 0.78)), CANOPY_RADII=Vector((0.36, 0.80, 0.42)),
        GUN_STATIONS=(("1", 0.30), ("2", 0.42)),
        GEAR_TRACK_X=1.24, GEAR_PIVOT_Y=-0.50, GEAR_AXLE=Vector((0.0, -0.62, -1.50)), GEAR_WHEEL_X=1.18,
        GEAR_WHEEL_RADIUS=0.38, GEAR_WHEEL_WIDTH=0.20, GEAR_FOLDS="in",
        TAIL_WHEEL_CENTRE=Vector((0.0, 5.55, -0.50)), TAIL_WHEEL_RADIUS=0.14, TAIL_WHEEL_WIDTH=0.10,
        TAIL_STRUT_TOP=Vector((0.0, 5.45, 0.10)),
        WING_ROOT_X=0.50, WING_BREAK_FRACTION=0.55, FIREWALL_Y=-0.45, TAIL_JOINT_Y=3.20, STABILISER_ROOT_X=0.10,
        FLAP_SPAN=(0.10, 0.52), FLAP_CHORD=0.22, AILERON_SPAN=(0.585, 0.92), AILERON_CHORD=0.24,
        ELEVATOR_SPAN=(0.12, 0.95), ELEVATOR_CHORD=0.42, RUDDER_SPAN=(0.04, 0.94), RUDDER_CHORD=0.45,
        EXHAUST=(0.44, -1.85, 0.28, 0.24),
        # The radiator bath under the centre section.
        FAIRINGS=[("Fuselage", [(0.10, 0.0, -0.74, 0.24, 0.06), (0.35, 0.0, -0.90, 0.40, 0.24),
                                (1.35, 0.0, -0.88, 0.40, 0.22), (1.70, 0.0, -0.72, 0.24, 0.06)])],
    ),
    # North American P-51D Mustang. Span 37 ft, length 32 ft 3 in, wing area
    # 235 sq ft (straight taper, square tips), track 11 ft 10 in, propeller
    # 11 ft 2 in with four blades, a bubble canopy and the radiator scoop
    # under the belly.
    "mustang": dict(
        FUSELAGE_STATIONS=[(-2.40, 0.36, 0.36, 0.10), (-2.05, 0.40, 0.46, 0.06), (-1.20, 0.42, 0.52, 0.02),
                           (-0.40, 0.44, 0.56, 0.00), (1.00, 0.44, 0.58, 0.00), (2.30, 0.38, 0.52, 0.06),
                           (4.00, 0.24, 0.38, 0.16), (5.50, 0.11, 0.24, 0.26), (6.20, 0.04, 0.10, 0.32)],
        TEAM_BAND_Y=(3.50, 4.10),
        WING_SPAN=11.28, WING_ROOT_CHORD=2.64, WING_THICKNESS=0.40, WING_DIHEDRAL_DEG=5.0,
        WING_CENTRE=Vector((0.0, 0.62, -0.50)), WING_PLANFORM=("taper", 0.20, 0.0, 0.48, 1.0), WING_TIP_ACCENT=0.80,
        TAILPLANE_SPAN=4.01, TAILPLANE_ROOT_CHORD=1.40, TAILPLANE_THICKNESS=0.15,
        TAILPLANE_CENTRE=Vector((0.0, 5.45, 0.38)), TAILPLANE_PLANFORM=("taper", 0.10, 0.0, 0.55, 1.0),
        FIN_HEIGHT=1.55, FIN_ROOT_CHORD=1.75, FIN_THICKNESS=0.14, FIN_BASE=Vector((0.0, 5.86, 0.34)),
        FIN_PLANFORM=("taper", 0.0, 0.0, 0.45, 0.88),
        SPINNER_RADIUS=0.36, SPINNER_LENGTH=0.75, PROP_RADIUS=1.70, PROP_BLADES=4, PROP_HUB=Vector((0.0, -2.70, 0.10)),
        CANOPY_CENTRE=Vector((0.0, 1.25, 0.60)), CANOPY_RADII=Vector((0.36, 0.98, 0.44)),
        GUN_STATIONS=(("1", 0.34), ("2", 0.42)),
        GEAR_TRACK_X=1.86, GEAR_PIVOT_Y=-0.50, GEAR_AXLE=Vector((0.0, -0.72, -1.505)), GEAR_WHEEL_X=1.805,
        GEAR_WHEEL_RADIUS=0.345, GEAR_WHEEL_WIDTH=0.19, GEAR_FOLDS="in",
        TAIL_WHEEL_CENTRE=Vector((0.0, 5.05, -0.45)), TAIL_WHEEL_RADIUS=0.16, TAIL_WHEEL_WIDTH=0.11,
        TAIL_STRUT_TOP=Vector((0.0, 4.95, 0.0)),
        WING_ROOT_X=0.44, WING_BREAK_FRACTION=0.56, FIREWALL_Y=-0.60, TAIL_JOINT_Y=3.10, STABILISER_ROOT_X=0.10,
        FLAP_SPAN=(0.10, 0.53), FLAP_CHORD=0.24, AILERON_SPAN=(0.595, 0.95), AILERON_CHORD=0.22,
        ELEVATOR_SPAN=(0.12, 0.95), ELEVATOR_CHORD=0.40, RUDDER_SPAN=(0.04, 0.94), RUDDER_CHORD=0.42,
        EXHAUST=(0.42, -1.95, 0.28, 0.20),
        # The radiator scoop under the belly.
        FAIRINGS=[("Fuselage", [(0.72, 0.0, -0.62, 0.20, 0.06), (0.95, 0.0, -0.82, 0.28, 0.22),
                                (2.20, 0.0, -0.76, 0.27, 0.20), (3.00, 0.0, -0.50, 0.16, 0.06)])],
    ),
}

# The planform in use: set by use_planform() before a surface is shaped or cut.
PLANFORM = ("ellipse", 0.25)


def apply_spec(name: str) -> None:
    """Makes one aeroplane's numbers the ones every function below reads."""
    globals().update(SPECS[name])


apply_spec("spitfire")

# --- Materials: (sRGB hex, alpha, metallic, roughness) -----------------------
MATERIAL_SPECS = {
    "BodyPrimary": ("4FB548", 1.0, 0.0, 0.55),            # Vibrant toy green.
    "WingAccent_TeamColor": ("1E78FF", 1.0, 0.0, 0.45),   # Team paint (blue).
    "CanopyGlass": ("9FE3FF", 0.38, 0.0, 0.08),           # Glossy, see-through.
    "MetalDark": ("2A2E36", 1.0, 0.85, 0.40),             # Gunmetal; also cut faces.
    "PropellerWood": ("B5713A", 1.0, 0.0, 0.70),          # Warm varnished wood.
    "PilotSkin": ("F2C79A", 1.0, 0.0, 0.65),
    "PilotLeather": ("6B4423", 1.0, 0.0, 0.60),           # Flying helmet.
}
# Slot order is identical on every part, so face material indices stay valid
# when parts are merged or cut.
MATERIAL_ORDER = list(MATERIAL_SPECS.keys())
BODY, ACCENT, GLASS, METAL, WOOD, SKIN, LEATHER = range(7)

# Build space -> final space: half a turn about the vertical axis.
TURN = Matrix.Rotation(math.pi, 4, 'Z')

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


def use_planform(planform) -> None:
    global PLANFORM
    PLANFORM = planform


def planform_chord(root_chord: float, fraction: float) -> float:
    """Chord at a span fraction (0 root .. 1 tip) for the planform in use."""
    fraction = min(abs(fraction), 1.0)
    if PLANFORM[0] == "ellipse":
        return root_chord * math.sqrt(max(1.0 - fraction * fraction, 0.0))
    _kind, _sweep, flat_to, tip_ratio, round_from = PLANFORM
    taper = min(max((fraction - flat_to) / (1.0 - flat_to), 0.0), 1.0)
    chord = root_chord * (1.0 + (tip_ratio - 1.0) * taper)
    if round_from < 1.0 and fraction > round_from:
        rounding = (fraction - round_from) / (1.0 - round_from)
        chord *= math.sqrt(max(1.0 - rounding * rounding, 0.0))
    return chord


def planform_centre_y(root_chord: float, fraction: float) -> float:
    """Outer sections slide forward (toward -Y in build space) as they get
    shorter, by the planform's sweep: 0.25 keeps the quarter-chord line
    straight, as on the Spitfire's ellipse."""
    return -PLANFORM[1] * (root_chord - planform_chord(root_chord, fraction))


def lifting_surface(bm: bmesh.types.BMesh, half_span: float, root_chord: float, thickness: float,
                    dihedral_deg: float = 0.0, both_sides: bool = True, loop_points: int = 8) -> None:
    """Wing-like slab in local space: span along X, chord along Y (leading edge
    toward -Y), thickness along Z. The planform is the one in use (see
    use_planform) and the section is a rounded oval."""
    fractions = [0.0, 0.30, 0.58, 0.80, 0.93, 0.985]
    stations = fractions if not both_sides else [-f for f in reversed(fractions[1:])] + fractions
    rise = math.tan(math.radians(dihedral_deg))
    rings = []
    for fraction in stations:
        chord = planform_chord(root_chord, abs(fraction))
        # Thickness shrinks a little slower than chord, as real wings' do.
        depth = thickness * (chord / root_chord) ** 0.8
        centre = Vector((fraction * half_span, planform_centre_y(root_chord, abs(fraction)), abs(fraction) * half_span * rise))
        rings.append(ellipse_ring(centre, Vector((0, 1, 0)), Vector((0, 0, 1)), chord * 0.5, depth * 0.5, loop_points))
    loft_rings(bm, rings)


def paint(bm: bmesh.types.BMesh, painter: FacePainter) -> None:
    """Assigns a material slot to every face from its centre position."""
    for face in bm.faces:
        face.material_index = painter(face.calc_center_median())


# =============================================================================
# Cage -> finished mesh (Bevel + Subdivision Surface, applied)
# =============================================================================

def evaluate_and_remove(temp: bpy.types.Object, name: str) -> bpy.types.Mesh:
    """Applies an object's modifier stack through the dependency graph, returns
    the resulting mesh and deletes the temporary object."""
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    result = bpy.data.meshes.new_from_object(temp.evaluated_get(depsgraph))
    result.name = name
    bpy.data.objects.remove(temp, do_unlink=True)
    return result


def finish_part(name: str, bm: bmesh.types.BMesh, materials: Sequence[bpy.types.Material],
                bevel_width: float = 0.0, bevel_segments: int = 1,
                subdiv_levels: int = DETAIL_SUBDIV) -> bpy.types.Mesh:
    """Turns a build-space cage into final geometry: fixes normals, adds the
    modifier stack (Bevel first so it holds the creases, then Subdivision
    Surface), applies it, and turns the result to face the final direction."""
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
    result = evaluate_and_remove(temp, name)
    bpy.data.meshes.remove(cage)
    result.transform(TURN)   # From here on everything is nose +Y, right wing +X.
    return result


def merge_meshes(name: str, parts: Sequence[bpy.types.Mesh], materials: Sequence[bpy.types.Material]) -> bpy.types.Mesh:
    """Joins meshes into one. The source meshes are deleted."""
    bm = bmesh.new()
    for part in parts:
        bm.from_mesh(part)
    merged = bpy.data.meshes.new(name)
    bm.to_mesh(merged)
    bm.free()
    for material in materials:
        merged.materials.append(material)
    for part in parts:
        bpy.data.meshes.remove(part)
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
# Cutting the plane into pieces (exact booleans, final space)
# =============================================================================

def prism(points: Sequence[tuple[float, float]], low: float, high: float, plane: str,
          materials: Sequence[bpy.types.Material]) -> bpy.types.Mesh:
    """A convex outline extruded into a solid cutter. `plane` says which plane
    the outline is drawn in: 'XY' (extruded along Z, for wing and tail cuts)
    or 'YZ' (extruded along X, for the rudder). Every face is given the dark
    metal slot, which is what the faces it cuts will be painted with."""
    def lift(u: float, v: float, w: float) -> Vector:
        return Vector((u, v, w)) if plane == 'XY' else Vector((w, u, v))
    bm = bmesh.new()
    lower = [bm.verts.new(lift(u, v, low)) for u, v in points]
    upper = [bm.verts.new(lift(u, v, high)) for u, v in points]
    count = len(points)
    bm.faces.new(lower)
    bm.faces.new(upper)
    for index in range(count):
        following = (index + 1) % count
        bm.faces.new((lower[index], lower[following], upper[following], upper[index]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for face in bm.faces:
        face.material_index = METAL
    mesh = bpy.data.meshes.new("cutter")
    bm.to_mesh(mesh)
    bm.free()
    for material in materials:
        mesh.materials.append(material)
    return mesh


def slab_x(x_low: float, x_high: float, materials: Sequence[bpy.types.Material]) -> bpy.types.Mesh:
    """Everything between two X positions."""
    return prism([(x_low, -20.0), (x_high, -20.0), (x_high, 20.0), (x_low, 20.0)], -20.0, 20.0, 'XY', materials)


def slab_y(y_low: float, y_high: float, materials: Sequence[bpy.types.Material]) -> bpy.types.Mesh:
    """Everything between two Y positions."""
    return prism([(-20.0, y_low), (20.0, y_low), (20.0, y_high), (-20.0, y_high)], -20.0, 20.0, 'XY', materials)


def boolean(target: bpy.types.Mesh, cutter: bpy.types.Mesh, operation: str, name: str) -> bpy.types.Mesh:
    """target (operation) cutter, as a new mesh. Neither input is modified.
    New faces take the cutter's material slot (dark metal)."""
    target_object = bpy.data.objects.new("bool_target", target)
    cutter_object = bpy.data.objects.new("bool_cutter", cutter)
    bpy.context.scene.collection.objects.link(target_object)
    bpy.context.scene.collection.objects.link(cutter_object)
    modifier = target_object.modifiers.new("Cut", 'BOOLEAN')
    modifier.operation = operation
    modifier.object = cutter_object
    modifier.solver = 'EXACT'
    if hasattr(modifier, "material_mode"):
        modifier.material_mode = 'INDEX'
    result = evaluate_and_remove(target_object, name)
    bpy.data.objects.remove(cutter_object, do_unlink=True)
    assert len(result.polygons) > 0, f"cutting produced an empty piece: {name}"
    return result


def keep_inside(target: bpy.types.Mesh, cutter: bpy.types.Mesh, name: str) -> bpy.types.Mesh:
    """The part of [target] inside [cutter]. The cutter is deleted."""
    result = boolean(target, cutter, 'INTERSECT', name)
    bpy.data.meshes.remove(cutter)
    return result


def cut_surface(source: bpy.types.Mesh, outline: Sequence[tuple[float, float]], plane: str, name: str,
                materials: Sequence[bpy.types.Material]) -> tuple[bpy.types.Mesh, bpy.types.Mesh]:
    """Cuts a control surface out of a wing/tail/fin.

    [outline] is the surface's footprint: first the two hinge points (inner,
    outer), then the two points far behind the trailing edge. Returns
    (what is left of the source with a notch, the surface). The notch is
    SURFACE_GAP bigger all round, which is the gap you see around a real
    control surface. The source mesh is deleted."""
    surface = keep_inside(source, prism(outline, -20.0, 20.0, plane, materials), name)
    # Grow the footprint about its centre for the notch.
    centre_u = sum(point[0] for point in outline) / len(outline)
    centre_v = sum(point[1] for point in outline) / len(outline)
    grown = []
    for u, v in outline:
        offset = Vector((u - centre_u, v - centre_v))
        offset = offset + offset.normalized() * SURFACE_GAP * 1.6
        grown.append((centre_u + offset.x, centre_v + offset.y))
    notch = prism(grown, -20.0, 20.0, plane, materials)
    remainder = boolean(source, notch, 'DIFFERENCE', source.name)
    bpy.data.meshes.remove(notch)
    bpy.data.meshes.remove(source)
    return remainder, surface


def crisp_edges(mesh: bpy.types.Mesh) -> None:
    """Smooth-shades a mesh but keeps its sharp edges (cut faces, steps) crisp
    by splitting them, which works the same in every Blender 4.x version."""
    bm = bmesh.new()
    bm.from_mesh(mesh)
    limit = math.radians(SHARP_ANGLE_DEG)
    sharp = [edge for edge in bm.edges if len(edge.link_faces) == 2 and edge.calc_face_angle(0.0) > limit]
    if sharp:
        bmesh.ops.split_edges(bm, edges=sharp)
    for face in bm.faces:
        face.smooth = True
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()


# =============================================================================
# Whole parts. Modelled nose-toward -Y (build space); finish_part() turns them.
# =============================================================================

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
    return finish_part("Fuselage", bm, materials, bevel_width=0.04, subdiv_levels=HERO_SUBDIV)


def to_span(mesh: bpy.types.Mesh, span: float) -> bpy.types.Mesh:
    """Rounding the cage off pulls the tips in a little: stretch the finished
    surface back out to exactly the span it was asked for."""
    reach = max(abs(vertex.co.x) for vertex in mesh.vertices)
    for vertex in mesh.vertices:
        vertex.co.x *= span * 0.5 / reach
    return mesh


def make_wing(materials) -> bpy.types.Mesh:
    use_planform(WING_PLANFORM)
    bm = bmesh.new()
    lifting_surface(bm, WING_SPAN * 0.5, WING_ROOT_CHORD, WING_THICKNESS, WING_DIHEDRAL_DEG)
    bmesh.ops.translate(bm, verts=bm.verts[:], vec=WING_CENTRE)
    tip_start = WING_SPAN * 0.5 * WING_TIP_ACCENT
    paint(bm, lambda centre: ACCENT if abs(centre.x) > tip_start else BODY)
    return to_span(finish_part("Wing", bm, materials, bevel_width=0.02, subdiv_levels=HERO_SUBDIV), WING_SPAN)


def make_tailplane(materials) -> bpy.types.Mesh:
    use_planform(TAILPLANE_PLANFORM)
    bm = bmesh.new()
    lifting_surface(bm, TAILPLANE_SPAN * 0.5, TAILPLANE_ROOT_CHORD, TAILPLANE_THICKNESS)
    bmesh.ops.translate(bm, verts=bm.verts[:], vec=TAILPLANE_CENTRE)
    tip_start = TAILPLANE_SPAN * 0.5 * 0.62
    paint(bm, lambda centre: ACCENT if abs(centre.x) > tip_start else BODY)
    return to_span(finish_part("Tailplane", bm, materials, bevel_width=0.015), TAILPLANE_SPAN)


def make_fin(materials) -> bpy.types.Mesh:
    use_planform(FIN_PLANFORM)
    bm = bmesh.new()
    lifting_surface(bm, FIN_HEIGHT, FIN_ROOT_CHORD, FIN_THICKNESS, both_sides=False)
    # Stand the half-wing up: local span (+X) becomes world +Z.
    bmesh.ops.transform(bm, verts=bm.verts[:], matrix=Matrix.Rotation(-math.pi / 2.0, 4, 'Y'))
    bmesh.ops.translate(bm, verts=bm.verts[:], vec=FIN_BASE)
    accent_from = FIN_BASE.z + FIN_HEIGHT * 0.45
    paint(bm, lambda centre: ACCENT if centre.z > accent_from else BODY)
    return finish_part("Fin", bm, materials, bevel_width=0.015)


def gun_mount(side: float, fraction: float) -> Vector:
    """Where a gun meets the wing's leading edge (build space)."""
    use_planform(WING_PLANFORM)
    half_span = WING_SPAN * 0.5
    chord = planform_chord(WING_ROOT_CHORD, fraction)
    return WING_CENTRE + Vector((
        side * fraction * half_span,
        planform_centre_y(WING_ROOT_CHORD, fraction) - chord * 0.5 + chord * 0.12,
        fraction * half_span * math.tan(math.radians(WING_DIHEDRAL_DEG)),
    ))


def make_gun(materials, side: float, fraction: float, kind: str) -> bpy.types.Mesh:
    """One wing gun sunk into the leading edge: a slim .303, a jacketed .50,
    or a fat 20 mm cannon with a muzzle brake."""
    bm = bmesh.new()
    lathe_y(bm, GUN_PROFILES[kind], 8)
    bmesh.ops.translate(bm, verts=bm.verts[:], vec=gun_mount(side, fraction))
    paint(bm, lambda _centre: METAL)
    return finish_part("Gun", bm, materials, bevel_width=0.008, subdiv_levels=0)


def nose_ring(share: float) -> tuple[float, float, float, float]:
    """(y, half_width, half_height, z_centre) of the cowling at a share of the
    way from the spinner (0) to the firewall (1)."""
    front = FUSELAGE_STATIONS[0][0]
    y = front + (FIREWALL_Y - front) * share
    for first, second in zip(FUSELAGE_STATIONS, FUSELAGE_STATIONS[1:]):
        if first[0] <= y <= second[0]:
            blend = (y - first[0]) / (second[0] - first[0])
            return (y,) + tuple(first[index] + (second[index] - first[index]) * blend for index in (1, 2, 3))
    return FUSELAGE_STATIONS[0]


def make_intake(materials) -> bpy.types.Mesh:
    """Chin intake of a two-stage supercharger, under the nose."""
    rings = []
    for share, half_width, half_height in ((0.12, 0.10, 0.06), (0.24, 0.16, 0.12), (0.75, 0.15, 0.12), (0.95, 0.06, 0.04)):
        y, _width, depth, middle = nose_ring(share)
        rings.append(ellipse_ring(Vector((0.0, y, middle - depth - half_height * 0.35)), Vector((1, 0, 0)), Vector((0, 0, 1)),
                                  half_width, half_height, 8))
    front_y = nose_ring(0.18)[0]
    bm = bmesh.new()
    loft_rings(bm, rings)
    paint(bm, lambda centre: METAL if centre.y < front_y else BODY)
    return finish_part("EngineIntake", bm, materials, bevel_width=0.015)


def make_cowl_bulges(materials) -> bpy.types.Mesh:
    """Blisters over the cylinder banks of a bigger engine."""
    parts = []
    for side in (-1.0, 1.0):
        rings = []
        for share, half_width, half_height in ((0.20, 0.02, 0.015), (0.32, 0.085, 0.065), (0.60, 0.10, 0.08), (0.80, 0.075, 0.055), (0.92, 0.02, 0.015)):
            y, width, depth, middle = nose_ring(share)
            rings.append(ellipse_ring(Vector((side * width * 0.52, y, middle + depth * 0.80)), Vector((1, 0, 0)), Vector((0, 0, 1)),
                                      half_width, half_height, 8))
        bm = bmesh.new()
        loft_rings(bm, rings)
        paint(bm, lambda _centre: BODY)
        parts.append(finish_part("Bulge", bm, materials, bevel_width=0.01))
    return merge_meshes("EngineBulges", parts, materials)


def make_fairing(materials, stations) -> bpy.types.Mesh:
    """A radiator or scoop: a short loft of ovals, dark at its open mouth."""
    rings = [ellipse_ring(Vector((x, y, z)), Vector((1, 0, 0)), Vector((0, 0, 1)), half_width, half_height, 8)
             for y, x, z, half_width, half_height in stations]
    mouth = stations[0][0] + (stations[1][0] - stations[0][0]) * 0.6
    bm = bmesh.new()
    loft_rings(bm, rings)
    paint(bm, lambda centre: METAL if centre.y < mouth else BODY)
    return finish_part("Fairing", bm, materials, bevel_width=0.015)


def make_slab(name: str, materials, centre: Vector, size: Vector, tilt_deg: float = 0.0) -> bpy.types.Mesh:
    """A flat steel plate: a box, optionally leaning back about the X axis."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, verts=bm.verts[:], vec=size)
    if tilt_deg != 0.0:
        bmesh.ops.rotate(bm, verts=bm.verts[:], cent=Vector((0, 0, 0)), matrix=Matrix.Rotation(math.radians(tilt_deg), 3, 'X'))
    bmesh.ops.translate(bm, verts=bm.verts[:], vec=centre)
    paint(bm, lambda _centre: METAL)
    return finish_part(name, bm, materials, bevel_width=0.008, subdiv_levels=0)


def make_tip_extension(materials, side: float) -> bpy.types.Mesh:
    """Pointed high-altitude wingtip that carries on where the standard tip ends."""
    use_planform(WING_PLANFORM)
    half_span = WING_SPAN * 0.5
    rise = math.tan(math.radians(WING_DIHEDRAL_DEG))
    root_chord = planform_chord(WING_ROOT_CHORD, WING_EXTENSION[0])
    root_depth = WING_THICKNESS * (root_chord / WING_ROOT_CHORD) ** 0.8
    rings = []
    for fraction, shrink in zip(WING_EXTENSION, (1.0, 0.62, 0.12)):
        centre = WING_CENTRE + Vector((side * fraction * half_span,
                                       planform_centre_y(WING_ROOT_CHORD, WING_EXTENSION[0]) - root_chord * 0.12 * (1.0 - shrink),
                                       fraction * half_span * rise))
        rings.append(ellipse_ring(centre, Vector((0, 1, 0)), Vector((0, 0, 1)), root_chord * 0.5 * shrink, root_depth * 0.5 * shrink, 8))
    if side < 0.0:
        rings.reverse()
    bm = bmesh.new()
    loft_rings(bm, rings)
    paint(bm, lambda _centre: ACCENT)
    return finish_part("TipExtension", bm, materials, bevel_width=0.01)


def strut(bm: bmesh.types.BMesh, start: Vector, end: Vector, radius: float, segments: int = 8) -> None:
    """A straight tube between two points."""
    along = (end - start).normalized()
    side_axis = along.cross(Vector((0.0, 1.0, 0.0)))
    if side_axis.length < 1e-4:
        side_axis = Vector((1.0, 0.0, 0.0))
    side_axis.normalize()
    other_axis = along.cross(side_axis).normalized()
    loft_rings(bm, [ellipse_ring(point, side_axis, other_axis, radius, radius, segments) for point in (start, end)])


def wheel(bm: bmesh.types.BMesh, centre: Vector, radius: float, width: float, segments: int = 14) -> None:
    """A fat tyre with a dished hub, axle along X."""
    half = width * 0.5
    profile = [(-half, radius * 0.50), (-half, radius * 0.90), (-half * 0.5, radius), (half * 0.5, radius),
               (half, radius * 0.90), (half, radius * 0.50)]
    rings = [ellipse_ring(centre + Vector((x, 0.0, 0.0)), Vector((0, 1, 0)), Vector((0, 0, 1)), ring_radius, ring_radius, segments)
             for x, ring_radius in profile]
    loft_rings(bm, rings)


def gear_pivot(side: float) -> Vector:
    """Where an undercarriage leg hinges, just inside the wing's underside."""
    rise = math.tan(math.radians(WING_DIHEDRAL_DEG))
    return Vector((side * GEAR_TRACK_X, GEAR_PIVOT_Y, WING_CENTRE.z + GEAR_TRACK_X * rise - WING_THICKNESS * 0.08))


def make_gear(materials, side: float, scale: float = 1.0) -> bpy.types.Mesh:
    """One main undercarriage unit: leg, wheel and door, modelled down and
    locked. The wheel is at the aeroplane's real track; the leg hinges in the
    wing and folds outward (the Spitfire, whose legs splay out from pivots
    close together) or inward (the others, whose legs hang from further out).
    [scale] fattens the leg and wheel for the reinforced version."""
    pivot = gear_pivot(side)
    wheel_radius = GEAR_WHEEL_RADIUS * scale
    wheel_width = GEAR_WHEEL_WIDTH * scale
    leg_radius = GEAR_LEG_RADIUS * scale * scale
    wheel_centre = Vector((side * GEAR_WHEEL_X, GEAR_AXLE.y, GEAR_AXLE.z - (wheel_radius - GEAR_WHEEL_RADIUS)))
    # The leg comes down beside the wheel: on its inboard side when the unit
    # folds outward, on its outboard side when it folds inward.
    leg_side = -side if GEAR_FOLDS == "out" else side
    leg_foot = wheel_centre + Vector((leg_side * (wheel_width * 0.5 + leg_radius + 0.02), 0.0, 0.0))
    parts = []

    bm = bmesh.new()
    strut(bm, pivot, leg_foot, leg_radius)
    strut(bm, leg_foot, wheel_centre, leg_radius * 0.8, 6)
    paint(bm, lambda _centre: METAL)
    parts.append(finish_part("GearLeg", bm, materials, bevel_width=0.01, subdiv_levels=0))

    bm = bmesh.new()
    wheel(bm, wheel_centre, wheel_radius, wheel_width)
    # Hub caps in the team colour, tyre in dark rubber.
    paint(bm, lambda centre: ACCENT if abs(centre.x - wheel_centre.x) > wheel_width * 0.49 else METAL)
    parts.append(finish_part("GearWheel", bm, materials, bevel_width=0.03, bevel_segments=2, subdiv_levels=0))

    # Door: a slab on the far side of the leg from the wheel, that closes the well.
    bm = bmesh.new()
    door_x = leg_foot.x + leg_side * (leg_radius + 0.03)
    top = Vector((door_x - leg_side * 0.03, pivot.y, pivot.z - 0.06))
    bottom = Vector((door_x, (pivot.y + GEAR_AXLE.y) * 0.5, GEAR_AXLE.z + wheel_radius * 1.1))
    rings = []
    for point, half_chord in ((top, 0.17), (bottom, 0.15)):
        rings.append([point + Vector((sx * 0.015, sy * half_chord, 0.0)) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))])
    loft_rings(bm, rings)
    paint(bm, lambda _centre: BODY)
    parts.append(finish_part("GearDoor", bm, materials, bevel_width=0.01, subdiv_levels=0))
    return merge_meshes("Gear", parts, materials)


def make_tail_wheel(materials) -> bpy.types.Mesh:
    """Tail wheel on a short strut."""
    parts = []
    bm = bmesh.new()
    strut(bm, TAIL_STRUT_TOP, TAIL_WHEEL_CENTRE + Vector((0.0, -0.01, 0.03)), 0.035, 6)
    paint(bm, lambda _centre: METAL)
    parts.append(finish_part("TailStrut", bm, materials, bevel_width=0.008, subdiv_levels=0))
    bm = bmesh.new()
    wheel(bm, TAIL_WHEEL_CENTRE, TAIL_WHEEL_RADIUS, TAIL_WHEEL_WIDTH, 10)
    paint(bm, lambda _centre: METAL)
    parts.append(finish_part("TailTyre", bm, materials, bevel_width=0.015, subdiv_levels=0))
    return merge_meshes("TailWheel", parts, materials)


def make_exhaust(materials, side: float, index: int) -> bpy.types.Mesh:
    """Exhaust stub on the cowling, swept back and outward."""
    out, first_y, step, height = EXHAUST
    bm = bmesh.new()
    lathe_y(bm, [(0.0, 0.045), (0.20, 0.055), (0.18, 0.03)], 6)
    # The pipe is built pointing aft (+Y here); swing it outward on its side.
    sweep = Matrix.Rotation(-side * math.radians(68.0), 4, 'Z')
    bmesh.ops.transform(bm, verts=bm.verts[:], matrix=sweep)
    bmesh.ops.translate(bm, verts=bm.verts[:], vec=Vector((side * out, first_y + index * step, height)))
    paint(bm, lambda _centre: METAL)
    # Too small for a bevel to read: Subdivision Surface alone rounds it off.
    return finish_part("Exhaust", bm, materials)


def make_headrest(materials) -> bpy.types.Mesh:
    """Seat back and headrest behind the pilot."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, verts=bm.verts[:], vec=Vector((0.58, 0.20, 0.70)) * PILOT_SCALE)
    bmesh.ops.translate(bm, verts=bm.verts[:], vec=CANOPY_CENTRE + Vector((0.0, 0.46, -0.04)) * PILOT_SCALE)
    paint(bm, lambda _centre: METAL)
    return finish_part("Headrest", bm, materials, bevel_width=0.02)


def make_pilot(materials) -> list[bpy.types.Mesh]:
    """Head, leather flying helmet and goggles: the pilot under the glass."""
    head_centre = CANOPY_CENTRE + Vector((0.0, 0.06, 0.04)) * PILOT_SCALE
    parts = []
    head = bmesh.new()
    bmesh.ops.create_uvsphere(head, u_segments=10, v_segments=6, radius=0.27 * PILOT_SCALE)
    bmesh.ops.translate(head, verts=head.verts[:], vec=head_centre)
    paint(head, lambda _centre: SKIN)
    parts.append(finish_part("PilotHead", head, materials))
    helmet = bmesh.new()
    bmesh.ops.create_uvsphere(helmet, u_segments=10, v_segments=6, radius=0.30 * PILOT_SCALE)
    bmesh.ops.scale(helmet, verts=helmet.verts[:], vec=Vector((1.0, 1.0, 0.82)))
    # Sits up and back, leaving the face (toward the nose, -Y here) uncovered.
    bmesh.ops.translate(helmet, verts=helmet.verts[:], vec=head_centre + Vector((0.0, 0.07, 0.07)) * PILOT_SCALE)
    paint(helmet, lambda _centre: LEATHER)
    parts.append(finish_part("PilotHelmet", helmet, materials))
    goggles = bmesh.new()
    bmesh.ops.create_cube(goggles, size=1.0)
    bmesh.ops.scale(goggles, verts=goggles.verts[:], vec=Vector((0.44, 0.10, 0.15)) * PILOT_SCALE)
    bmesh.ops.translate(goggles, verts=goggles.verts[:], vec=head_centre + Vector((0.0, -0.24, 0.05)) * PILOT_SCALE)
    paint(goggles, lambda _centre: METAL)
    parts.append(finish_part("PilotGoggles", goggles, materials, bevel_width=0.012))
    return parts


def make_canopy(materials) -> bpy.types.Mesh:
    """Bubble canopy: a stretched sphere whose lower half hides in the fuselage."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=6, radius=1.0)
    bmesh.ops.scale(bm, verts=bm.verts[:], vec=CANOPY_RADII)
    bmesh.ops.translate(bm, verts=bm.verts[:], vec=CANOPY_CENTRE)
    paint(bm, lambda _centre: GLASS)
    return finish_part("Canopy", bm, materials)


def make_spinner(materials) -> bpy.types.Mesh:
    """The nose cone on the propeller hub: from 0.30 m behind the hub to
    SPINNER_LENGTH ahead of that."""
    steps = 5
    profile = [(0.30, SPINNER_RADIUS * 0.96), (0.26, SPINNER_RADIUS)]
    for step in range(1, steps + 1):
        t = step / steps
        profile.append((0.26 - (SPINNER_LENGTH - 0.04) * t, SPINNER_RADIUS * math.sqrt(max(1.0 - t * t, 0.0)) + 0.015 * (1.0 - t)))
    bm = bmesh.new()
    lathe_y(bm, profile, 10)
    bmesh.ops.translate(bm, verts=bm.verts[:], vec=PROP_HUB)
    paint(bm, lambda _centre: ACCENT)
    return finish_part("Spinner", bm, materials, bevel_width=0.015)


def make_blade(materials, angle: float, width: float = 1.0) -> bpy.types.Mesh:
    """One propeller blade, twisted from root to tip. [width] broadens it."""
    # (share of the radius, half width, half thickness, pitch in degrees)
    sections = [(0.16, 0.06, 0.05, 55.0), (0.35, 0.11, 0.035, 42.0), (0.57, 0.13, 0.026, 30.0),
                (0.78, 0.12, 0.020, 22.0), (0.95, 0.08, 0.014, 17.0), (1.0, 0.04, 0.010, 15.0)]
    rings = []
    for share, half_width, half_thickness, pitch_deg in sections:
        pitch = Matrix.Rotation(math.radians(pitch_deg), 3, 'Z')
        rings.append(ellipse_ring(Vector((0.0, 0.0, share * PROP_RADIUS)), pitch @ Vector((1, 0, 0)), pitch @ Vector((0, 1, 0)),
                                  half_width * width, half_thickness, 8))
    bm = bmesh.new()
    loft_rings(bm, rings)
    bmesh.ops.transform(bm, verts=bm.verts[:], matrix=Matrix.Rotation(angle, 4, 'Y'))
    bmesh.ops.translate(bm, verts=bm.verts[:], vec=PROP_HUB)
    paint(bm, lambda _centre: WOOD)
    return finish_part("Blade", bm, materials, bevel_width=0.006)


# =============================================================================
# Hinge geometry (final space: nose +Y, right wing +X, up +Z)
# =============================================================================

def final_point(build_point: Vector) -> Vector:
    return (TURN @ build_point.to_4d()).to_3d()


def surface_edge_points(root_chord: float, fraction: float, chord_share: float) -> tuple[float, float]:
    """(hinge, far-behind) positions along the chord axis, in the surface's
    own build-space frame (leading edge -Y), for one span fraction."""
    chord = planform_chord(root_chord, fraction)
    trailing_edge = planform_centre_y(root_chord, fraction) + chord * 0.5
    return trailing_edge - chord * chord_share, trailing_edge + 3.0


def wing_surface_outline(span: tuple[float, float], chord_share: float, side: float) -> tuple[list[tuple[float, float]], Vector, Vector]:
    """Footprint (plan view, final space) and the two hinge end points in 3D
    for a flap or aileron. side: +1 right wing, -1 left wing."""
    use_planform(WING_PLANFORM)
    half_span = WING_SPAN * 0.5
    rise = math.tan(math.radians(WING_DIHEDRAL_DEG))
    outline = []
    ends = []
    behind = []
    for fraction in span:
        hinge, far = surface_edge_points(WING_ROOT_CHORD, fraction, chord_share)
        # Build space x is mirrored by TURN, so a point at build -x ends up on the right.
        build = WING_CENTRE + Vector((-side * fraction * half_span, hinge, fraction * half_span * rise))
        point = final_point(build)
        ends.append(point)
        outline.append((point.x, point.y))
        behind.append((point.x, final_point(WING_CENTRE + Vector((0.0, far, 0.0))).y))
    return [outline[0], outline[1], behind[1], behind[0]], ends[0], ends[1]


def elevator_outline(side: float) -> tuple[list[tuple[float, float]], Vector, Vector]:
    use_planform(TAILPLANE_PLANFORM)
    half_span = TAILPLANE_SPAN * 0.5
    outline = []
    ends = []
    behind = []
    for fraction in ELEVATOR_SPAN:
        hinge, far = surface_edge_points(TAILPLANE_ROOT_CHORD, fraction, ELEVATOR_CHORD)
        point = final_point(TAILPLANE_CENTRE + Vector((-side * fraction * half_span, hinge, 0.0)))
        ends.append(point)
        outline.append((point.x, point.y))
        behind.append((point.x, final_point(TAILPLANE_CENTRE + Vector((0.0, far, 0.0))).y))
    return [outline[0], outline[1], behind[1], behind[0]], ends[0], ends[1]


def rudder_outline() -> tuple[list[tuple[float, float]], Vector, Vector]:
    """Footprint in the side view (Y, Z) and the hinge's bottom and top."""
    use_planform(FIN_PLANFORM)
    outline = []
    ends = []
    behind = []
    for fraction in RUDDER_SPAN:
        hinge, far = surface_edge_points(FIN_ROOT_CHORD, fraction, RUDDER_CHORD)
        point = final_point(FIN_BASE + Vector((0.0, hinge, fraction * FIN_HEIGHT)))
        ends.append(point)
        outline.append((point.y, point.z))
        behind.append((final_point(FIN_BASE + Vector((0.0, far, 0.0))).y, point.z))
    return [outline[0], outline[1], behind[1], behind[0]], ends[0], ends[1]


def hinge_frame(start: Vector, end: Vector, axis: str) -> Matrix:
    """World matrix for a hinged piece: origin at the middle of the hinge line
    and the named local axis ('X' or 'Z') running along it.

    'X' is for surfaces that swing up and down: local X follows the hinge
    (always pointing toward the right wing), local Z stays as upright as it
    can. 'Z' is for the rudder: local Z follows the hinge upward."""
    origin = (start + end) * 0.5
    along = (end - start).normalized()
    if axis == 'X':
        x_axis = along if along.x >= 0.0 else -along
        z_axis = (Vector((0.0, 0.0, 1.0)) - x_axis * x_axis.z).normalized()
        y_axis = z_axis.cross(x_axis)
    else:
        z_axis = along if along.z >= 0.0 else -along
        x_axis = Vector((1.0, 0.0, 0.0))
        y_axis = z_axis.cross(x_axis).normalized()
        x_axis = y_axis.cross(z_axis)
    frame = Matrix.Identity(4)
    frame.col[0].xyz = x_axis
    frame.col[1].xyz = y_axis
    frame.col[2].xyz = z_axis
    frame.col[3].xyz = origin
    return frame


# =============================================================================
# Assembly and export
# =============================================================================

def new_piece(name: str, mesh: bpy.types.Mesh, world: Matrix, parent: bpy.types.Object | None) -> bpy.types.Object:
    """Wraps a final-space mesh in an object placed at [world]. The vertices
    are re-expressed in that frame, so the object's transform is exactly the
    pivot (and, for hinged pieces, the hinge direction) and nothing else."""
    mesh.transform(world.inverted())
    crisp_edges(mesh)
    remove_unused_material_slots(mesh)
    mesh.name = name
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.matrix_world = world
    if parent is not None:
        obj.parent = parent
        # Keep the world placement: the child's local transform becomes
        # "relative to the parent's pivot".
        obj.matrix_parent_inverse = parent.matrix_world.inverted()
    bpy.context.view_layer.update()
    return obj


def at(point: Vector) -> Matrix:
    return Matrix.Translation(point)


def triangle_count(mesh: bpy.types.Mesh) -> int:
    return sum(len(polygon.vertices) - 2 for polygon in mesh.polygons)


def build_plane() -> list[bpy.types.Object]:
    if CLEAR_SCENE:
        clear_scene()
    materials = build_materials()
    half_span = WING_SPAN * 0.5
    rise = math.tan(math.radians(WING_DIHEDRAL_DEG))
    firewall = -FIREWALL_Y          # Final-space Y of the engine | fuselage cut.
    tail_joint = -TAIL_JOINT_Y      # Final-space Y of the fuselage | tail cut.

    # --- Fuselage: one loft, cut into engine / centre / tail -----------------
    fuselage = make_fuselage(materials)
    engine_mesh = keep_inside(fuselage, slab_y(firewall, 20.0, materials), "Engine")
    centre_mesh = keep_inside(fuselage, slab_y(tail_joint, firewall, materials), "Fuselage")
    tail_mesh = keep_inside(fuselage, slab_y(-20.0, tail_joint, materials), "Tail")
    bpy.data.meshes.remove(fuselage)

    # --- Wing: cut out the four control surfaces, then split into panels -----
    wing = make_wing(materials)
    wing_surfaces = {}
    for side, tag in ((1.0, "R"), (-1.0, "L")):
        for label, span, chord_share in (("Flap", FLAP_SPAN, FLAP_CHORD), ("Aileron", AILERON_SPAN, AILERON_CHORD)):
            outline, hinge_start, hinge_end = wing_surface_outline(span, chord_share, side)
            wing, surface = cut_surface(wing, outline, 'XY', label + tag, materials)
            wing_surfaces[label + tag] = (surface, hinge_frame(hinge_start, hinge_end, 'X'))
    break_x = WING_BREAK_FRACTION * half_span
    wing_panels = {}
    for side, tag in ((1.0, "R"), (-1.0, "L")):
        inner = sorted((side * WING_ROOT_X, side * break_x))
        outer = sorted((side * break_x, side * 20.0))
        wing_panels["Wing" + tag] = keep_inside(wing, slab_x(inner[0], inner[1], materials), "Wing" + tag)
        wing_panels["WingTip" + tag] = keep_inside(wing, slab_x(outer[0], outer[1], materials), "WingTip" + tag)
        # Clipped wings: the same outer panel, cut short and squared off.
        clipped = sorted((side * break_x, side * WING_CLIP_FRACTION * half_span))
        wing_panels["WingTip" + tag + "_clipped"] = keep_inside(wing, slab_x(clipped[0], clipped[1], materials), "WingTip" + tag + "_clipped")
    wing_root = keep_inside(wing, slab_x(-WING_ROOT_X, WING_ROOT_X, materials), "WingRoot")
    bpy.data.meshes.remove(wing)

    # --- Tailplane: elevators out, then left and right stabilisers -----------
    tailplane = make_tailplane(materials)
    elevators = {}
    for side, tag in ((1.0, "R"), (-1.0, "L")):
        outline, hinge_start, hinge_end = elevator_outline(side)
        tailplane, surface = cut_surface(tailplane, outline, 'XY', "Elevator" + tag, materials)
        elevators["Elevator" + tag] = (surface, hinge_frame(hinge_start, hinge_end, 'X'))
    stabilisers = {
        "StabiliserR": keep_inside(tailplane, slab_x(STABILISER_ROOT_X, 20.0, materials), "StabiliserR"),
        "StabiliserL": keep_inside(tailplane, slab_x(-20.0, -STABILISER_ROOT_X, materials), "StabiliserL"),
    }
    tailplane_root = keep_inside(tailplane, slab_x(-STABILISER_ROOT_X, STABILISER_ROOT_X, materials), "TailplaneRoot")
    bpy.data.meshes.remove(tailplane)

    # --- Fin and rudder ------------------------------------------------------
    fin = make_fin(materials)
    outline, hinge_bottom, hinge_top = rudder_outline()
    fin, rudder_mesh = cut_surface(fin, outline, 'YZ', "Rudder", materials)
    rudder_frame = hinge_frame(hinge_bottom, hinge_top, 'Z')

    # --- Small parts join the piece they are bolted to -----------------------
    engine_mesh = merge_meshes("Engine", [engine_mesh] + [make_exhaust(materials, side, index)
                                                           for side in (-1.0, 1.0) for index in range(3)], materials)
    centre_mesh = merge_meshes("Fuselage", [centre_mesh, wing_root, make_headrest(materials)] + make_pilot(materials), materials)
    # Radiators and scoops join the piece they hang under.
    for target, stations in FAIRINGS:
        fairing = make_fairing(materials, stations)
        if target == "Fuselage":
            centre_mesh = merge_meshes("Fuselage", [centre_mesh, fairing], materials)
        elif target == "Engine":
            engine_mesh = merge_meshes("Engine", [engine_mesh, fairing], materials)
        else:
            wing_panels[target] = merge_meshes(target, [wing_panels[target], fairing], materials)
    tail_mesh = merge_meshes("Tail", [tail_mesh, tailplane_root], materials)
    propeller_mesh = merge_meshes("PropellerMesh", [make_spinner(materials)] + [
        make_blade(materials, math.tau * blade / PROP_BLADES) for blade in range(PROP_BLADES)], materials)
    propeller4_mesh = merge_meshes("PropellerMesh4", [make_spinner(materials)] + [
        make_blade(materials, math.tau * blade / 4.0, 1.15) for blade in range(4)], materials)
    canopy_mesh = make_canopy(materials)

    # --- Objects: pivots and hierarchy ---------------------------------------
    objects = []
    markers = []

    def piece(name: str, mesh: bpy.types.Mesh, world: Matrix, parent: bpy.types.Object | None) -> bpy.types.Object:
        obj = new_piece(name, mesh, world, parent)
        objects.append(obj)
        return obj

    body = piece("Fuselage", centre_mesh, Matrix.Identity(4), None)
    engine = piece("Engine", engine_mesh, at(Vector((0.0, firewall, 0.0))), body)
    piece("PropellerMesh", propeller_mesh, at(final_point(PROP_HUB)), engine)
    piece("PropellerMesh4", propeller4_mesh, at(final_point(PROP_HUB)), engine)
    piece("EngineIntake", make_intake(materials), at(Vector((0.0, firewall, 0.0))), engine)
    piece("EngineBulges", make_cowl_bulges(materials), at(Vector((0.0, firewall, 0.0))), engine)
    seat_plate = CANOPY_CENTRE + Vector((0.0, 0.32, -0.04))
    piece("ArmourSeat", make_slab("ArmourSeat", materials, seat_plate, Vector((0.46, 0.035, 0.44)), -8.0),
          at(final_point(seat_plate)), body)
    screen_plate = CANOPY_CENTRE + Vector((0.0, -CANOPY_RADII.y * 0.74, CANOPY_RADII.z * 0.42))
    piece("ArmourScreen", make_slab("ArmourScreen", materials, screen_plate, Vector((0.36, 0.04, 0.30)), 32.0),
          at(final_point(screen_plate)), body)
    piece("CanopyMesh", canopy_mesh, at(final_point(CANOPY_CENTRE)), body)
    tail = piece("Tail", tail_mesh, at(Vector((0.0, tail_joint, 0.12))), body)
    fin_object = piece("Fin", fin, at(final_point(FIN_BASE)), tail)
    piece("Rudder", rudder_mesh, rudder_frame, fin_object)
    piece("TailWheel", make_tail_wheel(materials), at(final_point(TAIL_STRUT_TOP)), tail)
    for tag, side in (("R", 1.0), ("L", -1.0)):
        stabiliser_root = final_point(TAILPLANE_CENTRE) + Vector((side * STABILISER_ROOT_X, 0.0, 0.0))
        piece("Stabiliser" + tag, stabilisers["Stabiliser" + tag], at(stabiliser_root), tail)
        surface, frame = elevators["Elevator" + tag]
        piece("Elevator" + tag, surface, frame, tail)

        wing_y = final_point(WING_CENTRE).y
        wing_z = WING_CENTRE.z
        root_pivot = Vector((side * WING_ROOT_X, wing_y, wing_z + WING_ROOT_X * rise))
        break_pivot = Vector((side * break_x, wing_y, wing_z + break_x * rise))
        panel = piece("Wing" + tag, wing_panels["Wing" + tag], at(root_pivot), body)
        surface, frame = wing_surfaces["Flap" + tag]
        piece("Flap" + tag, surface, frame, panel)
        # Guns: every type at every station, each its own piece with its
        # origin where it meets the leading edge. They belong to the wing
        # panel, so a lost wing takes its guns with it. Build -X is the right wing.
        for station, fraction in GUN_STATIONS:
            for kind in GUN_PROFILES:
                piece("Gun%s%s_%s" % (tag, station, kind), make_gun(materials, -side, fraction, kind),
                      at(final_point(gun_mount(-side, fraction))), panel)
        # Undercarriage: bolted to the inner panel, so it goes with the wing.
        # Its origin is the pivot; turning it about local Y folds it outward.
        piece("Gear" + tag, make_gear(materials, -side), at(final_point(gear_pivot(-side))), panel)
        piece("Gear" + tag + "_heavy", make_gear(materials, -side, HEAVY_GEAR_SCALE), at(final_point(gear_pivot(-side))), panel)
        tip = piece("WingTip" + tag, wing_panels["WingTip" + tag], at(break_pivot), panel)
        piece("WingTip" + tag + "_clipped", wing_panels["WingTip" + tag + "_clipped"], at(break_pivot), panel)
        extension_root = final_point(WING_CENTRE + Vector((-side * WING_EXTENSION[0] * half_span, 0.0, WING_EXTENSION[0] * half_span * rise)))
        piece("WingTipExt" + tag, make_tip_extension(materials, -side), at(extension_root), tip)
        surface, frame = wing_surfaces["Aileron" + tag]
        piece("Aileron" + tag, surface, frame, tip)

    # --- Sanity checks -------------------------------------------------------
    by_name = {obj.name: obj for obj in objects}
    propeller = by_name["PropellerMesh"]
    assert propeller.matrix_world.translation.y > 0.0, "nose must point along Blender +Y (Godot -Z)"
    assert by_name["WingR"].matrix_world.translation.x > 0.0 > by_name["WingL"].matrix_world.translation.x, "right wing must be +X"
    hinged = ("FlapL", "FlapR", "AileronL", "AileronR", "ElevatorL", "ElevatorR", "Rudder")
    for obj in objects:
        assert tuple(round(value, 5) for value in obj.matrix_world.to_scale()) == (1.0, 1.0, 1.0), f"{obj.name}: scale not applied"
        if obj.name not in hinged:
            rotation = obj.matrix_world.to_euler()
            assert max(abs(angle) for angle in rotation) < 1e-5, f"{obj.name}: rotation not applied"
    for name in hinged:
        mesh = by_name[name].data
        if name == "Rudder":
            ahead = max(vertex.co.y for vertex in mesh.vertices)   # Local +Y is toward the nose.
        else:
            ahead = max(vertex.co.y for vertex in mesh.vertices)
        assert ahead < SURFACE_GAP * 4.0, f"{name}: geometry should trail behind its hinge (found {ahead:.3f} ahead)"

    total = 0
    for obj in objects:
        triangles = triangle_count(obj.data)
        total += triangles
        parent_name = obj.parent.name if obj.parent else "-"
        slots = ", ".join(material.name for material in obj.data.materials)
        print(f"  {obj.name:<14} parent {parent_name:<10} {triangles:>5} tris   pivot {tuple(round(c, 2) for c in obj.matrix_world.translation)}   [{slots}]")
    print(f"  total {total} tris in {len(objects)} pieces at HERO_SUBDIV={HERO_SUBDIV}, DETAIL_SUBDIV={DETAIL_SUBDIV}")
    return objects + markers


def resolve_export_folder() -> str:
    """Optional folder after `--` on the command line; otherwise the game's
    assets/models beside this script, next to the .blend, or the home folder."""
    for argument in command_line_arguments():
        if "=" not in argument:
            return os.path.abspath(argument)
    script_path = globals().get("__file__", "")
    if script_path and os.path.isfile(script_path):
        return os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(script_path)), "..", "..", "assets", "models"))
    if bpy.data.filepath:
        return os.path.dirname(bpy.data.filepath)
    return os.path.expanduser("~")


def describe(name: str, objects: Sequence[bpy.types.Object]) -> None:
    """Prints the finished aeroplane's size, to check against the real one."""
    low = Vector((math.inf, math.inf, math.inf))
    high = -low
    for obj in objects:
        if obj.name in ("PropellerMesh4", "WingTipExtL", "WingTipExtR", "GearL_heavy", "GearR_heavy"):
            continue
        for vertex in obj.data.vertices:
            point = obj.matrix_world @ vertex.co
            low = Vector((min(low.x, point.x), min(low.y, point.y), min(low.z, point.z)))
            high = Vector((max(high.x, point.x), max(high.y, point.y), max(high.z, point.z)))
    contact = GEAR_AXLE.z - GEAR_WHEEL_RADIUS
    tail_contact = TAIL_WHEEL_CENTRE.z - TAIL_WHEEL_RADIUS
    wheelbase = TAIL_WHEEL_CENTRE.y - GEAR_AXLE.y
    sit = math.degrees(math.atan2(tail_contact - contact, wheelbase))
    print("%s: span %.2f m, length %.2f m, track %.2f m, propeller %.2f m; wheels %.2f m below and %.2f m ahead of the centre of gravity; sits %.1f degrees nose-up" % (
        name, high.x - low.x, high.y - low.y, GEAR_WHEEL_X * 2.0, PROP_RADIUS * 2.0, -contact, -GEAR_AXLE.y, sit))


def command_line_arguments() -> list[str]:
    return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


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
    for option in command_line_arguments():
        if option.startswith("hero="):
            HERO_SUBDIV = int(option.split("=", 1)[1])
    folder = resolve_export_folder()
    for plane_name in SPECS:
        apply_spec(plane_name)
        plane_objects = build_plane()
        describe(plane_name, plane_objects)
        export_glb(plane_objects, os.path.join(folder, plane_name + ".glb"))
