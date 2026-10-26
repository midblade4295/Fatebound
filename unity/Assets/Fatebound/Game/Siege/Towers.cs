// Ported from godot/scripts/siege/towers.gd (Fatebound 0.31.222).
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

    // The 5v5's towers (0.31.172, Kevin: "new tower models" -- the Royal A concepts for the lane tower and the King tower,
    // "I want them to visually break as their health gets lower").
    //
    // Two Meshy models (assets/meshy/towers/, made by tools/tower_prep.py): the lane tower for tiers 1-3 (a little bigger
    // each tier) and the King tower for tier 4. Each is drawn with tower.gdshader in its side's colours. A model is cut into
    // cells, each with the stage it breaks off at; as the tower's health falls past 75 / 50 / 25 % (stages 1 / 2 / 3) and
    // when it falls (4), that stage's cells are hidden in the tower's mesh and the view (siege_view.gd) drops a copy of
    // each (chunks()). Cracks spread with the damage taken. What's drawn follows the tower's health only -- the sim's
    // towers are unchanged.
    public class Towers
    {
        public static readonly Shader SHADER = ResourceLoader.Load<Shader>("res://scripts/siege/tower.gdshader");
        public const string DIR = "res://assets/meshy/towers/";
        public const string CRACKS = DIR + "cracks.png";
        // kind -> model; its height in metres at tier 1 (the King's own); the brazier (model units: the model is 1.0 tall, its
        // foot at y 0, its front on +Z) where the shots start; the foot's radius (model units) -- all from tools/tower_prep.py
        public static readonly GDict MODELS = new GDict
        {
            { "lane", GDict.Of("m", "tower_lane", "h", 6.0, "brazier", new Vector3(0.0, 0.638, -0.007), "foot", 0.193) },
            { "king", GDict.Of("m", "tower_king", "h", 7.0, "brazier", new Vector3(0.004, 0.641, 0.015), "foot", 0.285) },
        };
        public static readonly GArray TIER_SCALE = GArray.Of(1.0, 1.0, 1.07, 1.14, 1.0);      // by tier: the outer tower, the inner, the gate's, the King's
        public static readonly GArray STAGE_AT = GArray.Of(0.75, 0.5, 0.25);                  // health fractions at or under which stages 1, 2, 3 begin

        public static GDict _mats = new GDict();       // "kind|team" -> ShaderMaterial
        public static GDict _chunks = new GDict();     // kind -> [{mesh, center, stage}]

        public static string KindOf(int tier)
        {
            return tier >= 4 ? "king" : "lane";
        }

        public static double Height(int tier)
        {
            return (double)MODELS[KindOf(tier)]["h"] * (double)TIER_SCALE[GD.Clampi(tier, 0, 4)];
        }

        public static int StageOf(double hp, double max_hp, bool dead)
        {
            if (dead)
                return 4;
            var f = hp / GD.Maxf(max_hp, 1.0);
            var s = 0;
            for (int k = 0; k < STAGE_AT.Size(); k++)
            {
                if (f <= (double)STAGE_AT[k])
                    s = k + 1;
            }
            return s;
        }

        public static Vector3 Brazier(int tier)
        {
            // the brazier above the tower's foot, in metres (the tower turned to face +Z)
            return MODELS[KindOf(tier)]["brazier"].V3 * Height(tier);
        }

        public static ShaderMaterial Material(string kind, int team, Texture2D albedo)
        {
            var key = GD.Fmt("%s|%d", kind, team);
            if (_mats.Has(key))
                return _mats[key].As<ShaderMaterial>();
            var mat = new ShaderMaterial();
            mat.Shader = SHADER;
            mat.SetShaderParameter("team", team);
            mat.SetShaderParameter("albedo_tex", albedo);
            mat.SetShaderParameter("glow_tex", Stage.Texture(DIR + GD.Str(MODELS[kind]["m"]) + "_glow.png"));
            mat.SetShaderParameter("crack_tex", Stage.Texture(CRACKS));
            _mats[key] = Var.Of(mat);
            return mat;
        }

        public static Node3D Instance(int tier, int team)
        {
            // The tower for a tier, in a side's colours (team: the side as drawn, 0 blue / 1 red), its foot at the origin,
            // metres tall, front on +Z. Metas: "kind"; "mesh", its MeshInstance3D (the view sets broken / dmg / lit on it).
            var kind = KindOf(tier);
            var root = new Node3D();
            root.Name = "tower_" + kind;
            root.SetMeta("kind", kind);
            PackedScene packed = Stage.Scene(DIR + GD.Str(MODELS[kind]["m"]) + ".glb");
            if (packed == null)
                return root;
            Node3D m = packed.Instantiate() as Node3D;
            root.AddChild(m);
            m.Scale = Vector3.ONE * Height(tier);
            MeshInstance3D mi = null;
            foreach (var c in m.FindChildren("*", "MeshInstance3D", true, false))
            {
                mi = c as MeshInstance3D;
                break;
            }
            if (mi != null)
            {
                var src = mi.GetActiveMaterial(0) as BaseMaterial3D;
                mi.MaterialOverride = Material(kind, team, src != null ? src.AlbedoTexture : null);
                root.SetMeta("mesh", mi);
            }
            return root;
        }

        public static GArray Chunks(string kind, Mesh mesh)
        {
            // The model's cells as their own meshes (made once per model, the first time one breaks): each centred on its own
            // middle (model units) so it can tumble about it; its stage.
            if (_chunks.Has(kind))
                return _chunks[kind].A;
            var @out = new GArray();
            if (mesh == null || mesh.GetSurfaceCount() == 0)
            {
                _chunks[kind] = @out;
                return @out;
            }
            GArray a = mesh.SurfaceGetArrays(0);
            Vector3[] vs = a[Fatebound.GUI.Mesh.ARRAY_VERTEX].As<Vector3[]>();
            Vector3[] ns = a[Fatebound.GUI.Mesh.ARRAY_NORMAL].As<Vector3[]>();
            Vector2[] uv = a[Fatebound.GUI.Mesh.ARRAY_TEX_UV].As<Vector2[]>();
            Vector2[] uv2 = a[Fatebound.GUI.Mesh.ARRAY_TEX_UV2].As<Vector2[]>();
            int[] idx = a[Fatebound.GUI.Mesh.ARRAY_INDEX].As<int[]>();
            var tris = new GDict();                   // cell -> [vertex indices, three a triangle] (an Array: a packed one is a copy)
            for (int t = 0; t < idx.Length; t += 3)
            {
                var c = (int)GD.Round(uv2[idx[t]].y);
                if (!tris.Has(c))
                    tris[c] = new GArray();
                GArray l = tris[c].A;
                l.Append(idx[t]);
                l.Append(idx[t + 1]);
                l.Append(idx[t + 2]);
            }
            GArray cells = tris.Keys();
            cells.Sort();
            foreach (var c in cells)
            {
                GArray ti = tris[c].A;
                var remap = new GDict();
                var v2 = new List<Vector3>();
                var n2 = new List<Vector3>();
                var u2 = new List<Vector2>();
                var w2 = new List<Vector2>();
                var i2 = new List<int>();
                var mid = Vector3.ZERO;
                foreach (var vv in ti)
                {
                    int vi = (int)vv;
                    if (!remap.Has(vi))
                    {
                        remap[vi] = v2.Count;
                        v2.Add(vs[vi]);
                        n2.Add(ns[vi]);
                        u2.Add(uv[vi]);
                        w2.Add(uv2[vi]);
                        mid += vs[vi];
                    }
                    i2.Add((int)remap[vi]);
                }
                mid /= (double)GD.Maxi(v2.Count, 1);
                for (int k = 0; k < v2.Count; k++)
                    v2[k] -= mid;
                var arr = new GArray();
                arr.Resize(Fatebound.GUI.Mesh.ARRAY_MAX);
                arr[Fatebound.GUI.Mesh.ARRAY_VERTEX] = Var.Of(v2);
                arr[Fatebound.GUI.Mesh.ARRAY_NORMAL] = Var.Of(n2);
                arr[Fatebound.GUI.Mesh.ARRAY_TEX_UV] = Var.Of(u2);
                arr[Fatebound.GUI.Mesh.ARRAY_TEX_UV2] = Var.Of(w2);
                arr[Fatebound.GUI.Mesh.ARRAY_INDEX] = Var.Of(i2);
                var am = new ArrayMesh();
                am.AddSurfaceFromArrays(Fatebound.GUI.Mesh.PRIMITIVE_TRIANGLES, arr);
                @out.Append(GDict.Of("mesh", Var.Of(am), "center", mid, "stage", (int)GD.Round(uv2[(int)ti[0]].x), "tris", ti.Size() / 3));
            }
            _chunks[kind] = @out;
            return @out;
        }
    }
}
