extends Resource
class_name SiegeTerrainCache
# Everything the view used to generate in GDScript at every first match start (0.31.8): the terrain and outer-land
# meshes, the foliage plan (MultiMesh transforms per kind) and the blood textures. Baked by tools/bake_land.gd into
# assets/terrain/cache.res; siege_view.gd loads it when `key` matches Land.bake_key() and generates otherwise.
@export var key := ""
@export var terrain: Array = []          # ArrayMesh per 32 m band
@export var outer: Array = []            # ArrayMesh per ring
@export var foliage: Dictionary = {}     # kind -> Array[Transform3D]
@export var blood: Array = []            # 5 Images (4 splats, 1 pool)
