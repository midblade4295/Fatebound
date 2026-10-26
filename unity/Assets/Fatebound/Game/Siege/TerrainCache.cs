// Ported from godot/scripts/siege/terrain_cache.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;

namespace Fatebound.Game
{
    // class_name SiegeTerrainCache
    // Everything the view used to generate in GDScript at every first match start (0.31.8): the terrain and outer-land
    // meshes, the foliage plan (MultiMesh transforms per kind) and the blood textures. Baked by tools/bake_land.gd into
    // assets/terrain/cache.res; siege_view.gd loads it when `key` matches Land.bake_key() and generates otherwise.
    public class TerrainCache : Resource
    {
        public string key = "";
        public GArray terrain = new GArray();          // ArrayMesh per 32 m band
        public GArray outer = new GArray();            // ArrayMesh per ring
        public GDict foliage = new GDict();            // kind -> Array[Transform3D]
        public GDict outer_trees = new GDict();        // "side:type" -> Array[Transform3D] (0.31.78)
        public GArray blood = new GArray();            // 5 Images (4 splats, 1 pool)
    }
}
