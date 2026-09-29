# Low-poly stylized flowers for scattering on the terrain (Kevin's references have red, blue,
# yellow and white flowers dotted over the grass). One GLB per colour: assets/terrain/flower_<c>.glb
#   xvfb-run -a blender -b --python godot/tools/blender/flowers.py
# Each flower: stem, two leaves, 5 petals around a yellow (or orange) centre, ~0.45 m tall so it
# reads from the game camera. Origin at the ground.
import bpy, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(os.path.join(HERE, "../../assets/terrain"))
COLOURS = {  # linear colours
    "red":    ((0.85, 0.03, 0.03), (1.0, 0.72, 0.05)),
    "blue":   ((0.05, 0.22, 0.95), (1.0, 0.85, 0.12)),
    "yellow": ((1.0, 0.72, 0.02), (0.85, 0.28, 0.02)),
    "white":  ((0.92, 0.92, 0.95), (1.0, 0.72, 0.05)),
}
def mat(name, c, rough=0.6):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs['Base Color'].default_value = (*c, 1)
    b.inputs['Roughness'].default_value = rough
    return m
for name, (petal_c, centre_c) in COLOURS.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    stem_m = mat("stem", (0.04, 0.28, 0.02))
    petal_m = mat("petal", petal_c, 0.5)
    centre_m = mat("centre", centre_c, 0.5)
    parts = []
    bpy.ops.mesh.primitive_cylinder_add(vertices=5, radius=0.018, depth=0.34, location=(0, 0, 0.17))
    o = bpy.context.active_object; o.data.materials.append(stem_m); parts.append(o)
    for side in (-1, 1):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=4, ring_count=2, radius=0.06, location=(side * 0.05, 0, 0.1))
        o = bpy.context.active_object
        o.scale = (1.0, 0.35, 0.25); o.rotation_euler = (0, side * 0.6, 0)
        o.data.materials.append(stem_m); parts.append(o)
    for k in range(5):
        a = k * 2 * math.pi / 5
        bpy.ops.mesh.primitive_uv_sphere_add(segments=5, ring_count=3, radius=0.07,
            location=(math.cos(a) * 0.075, math.sin(a) * 0.075, 0.37))
        o = bpy.context.active_object
        o.scale = (1.0, 0.62, 0.22); o.rotation_euler = (0.25, 0, a)
        o.data.materials.append(petal_m); parts.append(o)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=6, ring_count=3, radius=0.045, location=(0, 0, 0.39))
    o = bpy.context.active_object; o.scale = (1, 1, 0.6); o.data.materials.append(centre_m); parts.append(o)
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    bpy.ops.object.join()
    bpy.ops.object.shade_flat()
    out = os.path.join(OUT, "flower_%s.glb" % name)
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_apply=True)
    print("FLOWER_DONE", name, flush=True)
