// Ported from godot/scripts/siege/foliage.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector3 = Fatebound.Sim.Vec3;
using Color = Fatebound.GUI.Col;

namespace Fatebound.Game
{
    using Stage = Fatebound.Game.AssetCache;

    // The Rift's trees and bushes (0.31.173, Kevin: "I want better trees and bush models" -- all sixteen of the Summer and
    // Enchanted concepts). Meshy models (assets/meshy/foliage/, tools/foliage_prep.py), drawn by the view as MultiMeshes
    // with foliage.gdshader (the canopies sway; the glowing fruits and flowers shine). This file says which plant goes
    // where; the view (siege_view.gd: _plan_ridges, _build_brush, _build_outer_trees, _build_edge_scenery) places them.
    public class Foliage
    {
        public static readonly Shader SHADER = ResourceLoader.Load<Shader>("res://scripts/siege/foliage.gdshader");
        public const string DIR = "res://assets/meshy/foliage/";

        // every plant: its sway (model units at the top), the still share of its height, glow strength
        public static readonly GDict PLANTS = new GDict
        {
            { "tree_oak", GDict.Of("sway", 0.10, "from", 0.40) }, { "tree_fir", GDict.Of("sway", 0.08, "from", 0.30) }, { "tree_birch", GDict.Of("sway", 0.13, "from", 0.35) },
            { "tree_gnarled", GDict.Of("sway", 0.08, "from", 0.45) }, { "tree_mossy", GDict.Of("sway", 0.10, "from", 0.40) }, { "tree_blossom", GDict.Of("sway", 0.10, "from", 0.40) },
            { "tree_glow", GDict.Of("sway", 0.09, "from", 0.40, "glow", 2.2) }, { "tree_autumn", GDict.Of("sway", 0.10, "from", 0.40) },
            { "bush_round", GDict.Of("sway", 0.03, "from", 0.2) }, { "bush_flower", GDict.Of("sway", 0.03, "from", 0.2) }, { "bush_fern", GDict.Of("sway", 0.05, "from", 0.15) },
            { "grass_reeds", GDict.Of("sway", 0.09, "from", 0.1) }, { "bush_berry", GDict.Of("sway", 0.03, "from", 0.2) }, { "bush_broadleaf", GDict.Of("sway", 0.05, "from", 0.15) },
            { "grass_glow", GDict.Of("sway", 0.07, "from", 0.1, "glow", 2.0) }, { "grass_tall", GDict.Of("sway", 0.09, "from", 0.1) },
        };
        // the trees along the jungle's walls: mostly greens, a blossom, an autumn tree or a glowing one here and there
        public static readonly GDict RIDGE_TREES = GDict.Of("tree_oak", 3, "tree_mossy", 3, "tree_fir", 2, "tree_birch", 2, "tree_gnarled", 2, "tree_blossom", 1,
            "tree_autumn", 1, "tree_glow", 1);
        // under them
        public static readonly GDict RIDGE_BUSHES = GDict.Of("bush_round", 2, "bush_fern", 2, "bush_broadleaf", 2, "bush_berry", 1, "bush_flower", 1);
        // the woods beyond the field (the light copies, *_far: Meshy's first, lighter takes, 1.3-1.9k triangles)
        public static readonly GDict OUTER_TREES = GDict.Of("tree_oak", 3, "tree_mossy", 3, "tree_fir", 3, "tree_birch", 2, "tree_autumn", 1);
        // a brush patch is one of these sets: tall grass (League's brush), a leafy thicket, an enchanted thicket
        public static readonly GArray BRUSH_SETS = GArray.Of(GDict.Of("grass_reeds", 3, "grass_tall", 3, "bush_fern", 1),
            GDict.Of("bush_round", 3, "bush_flower", 2, "bush_fern", 2),
            GDict.Of("bush_berry", 2, "bush_broadleaf", 2, "grass_glow", 2));

        // a brush plant's size (its instance scale; the models: the bushes 1 m across, the grasses 1 m tall): a hero's height
        // or more, overlapping -- a thicket you can see you'd hide in (the KayKit bushes' brush stood about as tall)
        public static double BrushScale(Rng rng, string kind)
        {
            return kind.BeginsWith("grass") ? rng.RandfRange(1.45, 1.8) : rng.RandfRange(1.9, 2.4);
        }

        public static GDict _mats = new GDict();
        public static GDict _meshes = new GDict();

        public static string Pick(Rng rng, GDict weights)
        {
            var total = 0;
            foreach (var k in weights)
                total += (int)weights[k];
            long x = (long)rng.Randi() % GD.Maxi(total, 1);
            foreach (var k in weights)
            {
                x -= (int)weights[k];
                if (x < 0)
                    return GD.Str(k);
            }
            return GD.Str(weights.Keys()[0]);
        }

        public static string Path(string kind)
        {
            return DIR + kind + ".glb";
        }

        // a plant's own name without its copy's suffix: *_far (the woods beyond the field: an earlier, lighter Meshy take),
        // *_shadow (the same model remeshed by Meshy to ~1000 triangles, its canopy pulled in a little: what a tree's shadow
        // is drawn from -- siege_view._plant_batch)
        public static string Base(string kind)
        {
            return kind.TrimSuffix("_far").TrimSuffix("_shadow");
        }

        public static bool IsPlant(string kind)
        {
            return PLANTS.Has(Base(kind));
        }

        // the light copy a tree's shadow is drawn from ("" for a plant without one: the bushes cast none)
        public static string ShadowOf(string kind)
        {
            return Base(kind).BeginsWith("tree") ? Base(kind) + "_shadow" : "";
        }

        public static Mesh Mesh(string kind)
        {
            if (!_meshes.Has(kind))
            {
                Mesh m = null;
                PackedScene packed = Stage.Scene(Path(kind));
                if (packed != null)
                {
                    var holder = packed.Instantiate();
                    foreach (var c in holder.FindChildren("*", "MeshInstance3D", true, false))
                    {
                        m = (c as MeshInstance3D).Mesh;
                        if (!_mats.Has(kind))
                            _MaterialFrom(kind, c as MeshInstance3D, m);
                        break;
                    }
                    holder.Free();
                }
                _meshes[kind] = Var.Of(m);
            }
            return _meshes[kind].As<Mesh>();
        }

        public static GMaterial Material(string kind)
        {
            if (!_mats.Has(kind))
                Mesh(kind);
            return _mats.Get(kind, Var.Nil).As<GMaterial>();
        }

        public static void _MaterialFrom(string kind, MeshInstance3D mi, Mesh m)
        {
            GDict spec = PLANTS.Get(Base(kind), new GDict()).D;
            var mat = new ShaderMaterial();
            mat.Shader = SHADER;
            var src = mi.GetActiveMaterial(0) as BaseMaterial3D;
            mat.SetShaderParameter("albedo_tex", src != null ? src.AlbedoTexture : null);
            mat.SetShaderParameter("height", m != null ? GD.Maxf(m.GetAabb().size.y, 0.1) : 1.0);
            mat.SetShaderParameter("sway", (double)spec.Get("sway", 0.08));
            mat.SetShaderParameter("sway_from", (double)spec.Get("from", 0.3));
            if (spec.Has("glow"))
            {
                mat.SetShaderParameter("glow_tex", Stage.Texture(DIR + Base(kind) + "_glow.png"));
                mat.SetShaderParameter("glow_energy", (double)spec["glow"]);
            }
            _mats[kind] = Var.Of(mat);
        }
    }
}
