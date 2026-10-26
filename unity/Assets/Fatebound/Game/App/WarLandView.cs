// Ported from godot/scripts/app/war_land_view.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector3 = Fatebound.Sim.Vec3;
using Vector4 = Fatebound.Sim.Vec4;
using Color = Fatebound.GUI.Col;
using Transform3D = Fatebound.Sim.Xform3;
using SocialUI = Fatebound.Game.SocialUi;
using UI2 = Fatebound.Game.Ui2;
using Map = Fatebound.Game.WarMap;
using Stage = Fatebound.Game.AssetCache;
using LandData = Fatebound.Game.WarLandData;   // (tools/war_land.py: the grid, each place's spot)

namespace Fatebound.Game
{
    // 0.31.138: the war map's land as one piece (until now built inside war_table.gd), so that Home's war table
    // (war_room.gd) stands the same live map on its table: the land (tools/war_land.py), the sea round it, the forests'
    // trees, each place's Meshy miniature (0.31.136) and the crossed swords over a battle. `paint` shows the war on it (who
    // holds each place, the battles, the place picked); `step` moves it (the miniature picked lifts, swords bob).
    // Map space is this node's own: x right, z toward the viewer, 1 = one map unit (the land is 12 x 18). Moved or scaled
    // (Home's table), the shaders follow through `to_map` -- call `placed()` once it is where it stays.
    public class WarLandView : Node3D
    {
        public static readonly Shader LandShader = ResourceLoader.Load<Shader>("res://scripts/app/war_land.gdshader");
        public static readonly Shader SeaShader = ResourceLoader.Load<Shader>("res://scripts/app/war_sea.gdshader");
        public const string LAND = "res://assets/war_land/";
        public const string PIECES = "res://assets/meshy/war/";   // each place's Meshy miniature (0.31.136, tools/meshy_war_piece.py)
        public static readonly Color TREE_TINT = new Color(0.62, 0.8, 0.5);
        public const double RAISE = 0.14;                          // the place picked lifts its miniature a little
        public const double SWORDS_UP = 1.35;                      // the crossed swords float this high over a battle's place

        public ShaderMaterial land_mat;
        public ShaderMaterial sea_mat;
        public Image region_img;                        // (picking: which place's land a tap is on)
        public GDict tiles = new GDict();                              // id -> {"pos": Vector3 (its ground), "node": Node3D or null, "swords": Sprite3D}
        public Vector2 disc = Vector2.ZERO;                     // not zero: cut to this oval, its x and z radii (Home's table)
        public double sea_size = 80.0;
        public double _clock = 0.0;

        public static Vector3 TilePos(string id)
        {
            // a place's spot on the land (x right, z toward you; the Lions near, the Stags far, the Ravens east)
            GDict e = LandData.PLACES.Get(id, new GDict()).D;
            return new Vector3((double)e.Get("x", 0.0), (double)e.Get("y", 0.0), (double)e.Get("z", 0.0));
        }

        public static NoiseTexture2D NoiseTex(double freq, int seed, int size = 256)
        {
            var n = new FastNoiseLite();
            n.Seed = seed;
            n.Frequency = freq;
            n.FractalOctaves = 4;
            var t = new NoiseTexture2D();
            t.Width = size;
            t.Height = size;
            t.Seamless = true;
            t.Noise = n;
            return t;
        }

        public void Build(double swords_px = 0.0045, double glow = 0.0)
        {
            Texture2D regions = Stage.Texture(LAND + "land_regions.png");
            var clouds = NoiseTex(0.006, 7);
            // the land
            PackedScene land_scene = Stage.Scene(LAND + "land.glb");
            if (land_scene != null)
            {
                var land = land_scene.Instantiate() as Node3D;
                AddChild(land);
                land_mat = new ShaderMaterial();
                land_mat.Shader = LandShader;
                land_mat.SetShaderParameter("color_tex", Stage.Texture(LAND + "land_color.jpg"));
                land_mat.SetShaderParameter("region_id", regions);
                land_mat.SetShaderParameter("region_lin", regions);
                land_mat.SetShaderParameter("cloud_tex", clouds);
                land_mat.SetShaderParameter("disc", disc);
                land_mat.SetShaderParameter("glow", glow);
                foreach (var mi in land.FindChildren("*", "MeshInstance3D", true, false))
                    (mi as MeshInstance3D).MaterialOverride = land_mat;
            }
            if (regions != null)
            {
                region_img = regions.GetImage();
                if (region_img != null && region_img.IsCompressed())
                    region_img.Decompress();
            }
            // the sea (and the lake, the river, the pools): one sheet at sea level
            var sea = new MeshInstance3D();
            var pm = new PlaneMesh();
            pm.Size = new Vector2(sea_size, sea_size);
            sea.Mesh = pm;
            sea_mat = new ShaderMaterial();
            sea_mat.Shader = SeaShader;
            sea_mat.SetShaderParameter("region_lin", regions);
            sea_mat.SetShaderParameter("wave_tex", NoiseTex(0.02, 3));
            sea_mat.SetShaderParameter("cloud_tex", clouds);
            sea_mat.SetShaderParameter("map_rect", new Vector4(LandData.X0, LandData.Z0, LandData.X1 - LandData.X0, LandData.Z1 - LandData.Z0));
            sea_mat.SetShaderParameter("h_min", LandData.H_MIN);
            sea_mat.SetShaderParameter("h_max", LandData.H_MAX);
            sea_mat.SetShaderParameter("disc", disc);
            sea_mat.SetShaderParameter("glow", glow);
            sea.MaterialOverride = sea_mat;
            sea.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
            AddChild(sea);
            // the forests' trees (KayKit's, many at once)
            _PlantTrees();
            // the places: each miniature standing in its land (sunk so its base hides under the ground), crossed swords
            // over a battle
            Texture2D swords_tex = Stage.Texture(UI2.IconPath("swords"));
            foreach (var idv in Map.T)
            {
                string id = idv.AsString();
                var pos = TilePos(id);
                GDict e2 = LandData.PLACES.Get(id, new GDict()).D;
                Node3D node = null;
                string piece = PIECES + GD.Str(e2.Get("piece", "")) + ".glb";
                if (GD.Str(e2.Get("piece", "")) != "" && ResourceLoader.Exists(piece))
                {
                    node = new Node3D();
                    node.Position = pos;
                    AddChild(node);
                    var m = (Stage.Scene(piece) as PackedScene).Instantiate() as Node3D;
                    m.Scale = Vector3.ONE * (double)e2.Get("scale", 0.5);
                    { var mp = m.Position; mp.y = (float)(double)e2.Get("sink", 0.0); m.Position = mp; }
                    { var mr = m.Rotation; mr.y = (float)GD.DegToRad((double)e2.Get("yaw", 0.0)); m.Rotation = mr; }
                    node.AddChild(m);
                }
                var sw = new Sprite3D();
                sw.Texture = swords_tex;
                sw.Billboard = (BillboardMode)BaseMaterial3D.BILLBOARD_ENABLED;
                sw.PixelSize = swords_px;
                sw.NoDepthTest = true;
                sw.Position = pos + new Vector3(0.0, SWORDS_UP, 0.0);
                sw.Visible = false;
                AddChild(sw);
                tiles[id] = new GDict { { "pos", pos }, { "node", node }, { "swords", sw } };
            }
            Placed();
        }

        public void Placed()
        {
            // the shaders' map space: this node's own, wherever it stands
            var inv = IsInsideTree() ? GlobalTransform.AffineInverse() : Transform.AffineInverse();
            var m = new Projection(inv);
            if (land_mat != null)
                land_mat.SetShaderParameter("to_map", m);
            if (sea_mat != null)
                sea_mat.SetShaderParameter("to_map", m);
        }

        public void _PlantTrees()
        {
            var kinds = GArray.Of("tree_single_A", "tree_single_B");
            for (int k = 0; k < kinds.Size(); k++)
            {
                PackedScene ps = Stage.Scene(GD.Fmt("res://assets/kaykit/hex/%s.gltf", kinds[k]));
                if (ps == null)
                    continue;
                var inst = ps.Instantiate();
                var mis = inst.FindChildren("*", "MeshInstance3D", true, false);
                if (mis.Count == 0)
                {
                    inst.Free();
                    continue;
                }
                var mi = mis[0] as MeshInstance3D;
                Mesh mesh = mi.Mesh;
                var @base = mi.Transform;
                inst.Free();
                var list = new GArray();
                foreach (var t in LandData.TREES)
                {
                    if ((int)t[4] == k)
                        list.Append(t);
                }
                var mm = new MultiMesh();
                mm.TransformFormat = MultiMesh.TRANSFORM_3D;
                mm.Mesh = mesh;
                mm.InstanceCount = list.Size();
                for (int i = 0; i < list.Size(); i++)
                {
                    GArray t = list[i].A;
                    var sc = (double)t[3];
                    var b = new Basis(Vector3.UP, GD.Fmod((double)t[0] * 12.7 + (double)t[2] * 7.3, GD.TAU)).Scaled(Vector3.ONE * sc);
                    mm.SetInstanceTransform(i, new Transform3D(b, new Vector3((double)t[0], (double)t[1] - 0.02, (double)t[2])) * @base);
                }
                var mmi = new MultiMeshInstance3D();
                mmi.Multimesh = mm;
                var src = mesh.SurfaceGetMaterial(0) as StandardMaterial3D;
                if (src != null)
                {
                    var tm = src.Duplicate() as StandardMaterial3D;
                    tm.AlbedoColor = src.AlbedoColor * TREE_TINT;                // (KayKit's teal leaves: a deeper green)
                    mmi.MaterialOverride = tm;
                }
                AddChild(mmi);
            }
        }

        public string RegionOf(Vector3 map_pt)
        {
            // which place's land is at a point of map space ("" for the sea)
            if (region_img == null)
                return "";
            var u = (map_pt.x - LandData.X0) / (LandData.X1 - LandData.X0);
            var v = (map_pt.z - LandData.Z0) / (LandData.Z1 - LandData.Z0);
            if (u < 0.0 || v < 0.0 || u >= 1.0 || v >= 1.0)
                return "";
            var px = region_img.GetPixel(GD.Int(u * region_img.GetWidth()), GD.Int(v * region_img.GetHeight()));
            var idx = GD.Int(GD.Round(px.r * 255.0));
            return idx < LandData.IDS.Size() ? GD.Str(LandData.IDS[idx]) : "";
        }

        public void Paint(GDict war, string sel = "")
        {
            // the war on the land: each place tinted with its holder's colour, battles pulsing (and their swords), the place picked
            GDict terr = war.Get("terr", new GDict()).D;
            var holders = new List<Color>();
            var battles = new List<float>();
            for (int i = 0; i < LandData.IDS.Size(); i++) holders.Add(new Color(0, 0, 0, 1));     // (resize(): Color() is (0, 0, 0, 1))
            for (int i = 0; i < LandData.IDS.Size(); i++) battles.Add(0f);
            foreach (var idv in tiles)
            {
                string id = idv.AsString();
                GDict t = terr.Get(id, new GDict()).D;
                var h = GD.Str(t.Get("h", ""));
                Color col = h != "" ? SocialUI.HouseColor(h) : new Color(0.85, 0.85, 0.8);
                var k = LandData.IDS.Find(id);
                if (k >= 0)
                {
                    holders[k] = new Color(col.r, col.g, col.b, h != "" ? 1.0 : 0.0);
                    battles[k] = t.Has("b") ? 1.0f : 0.0f;
                }
                (tiles[id]["swords"].As<Sprite3D>()).Visible = t.Has("b");
            }
            if (land_mat != null)
            {
                land_mat.SetShaderParameter("holder", holders);
                land_mat.SetShaderParameter("battle", battles);
                land_mat.SetShaderParameter("picked", LandData.IDS.Find(sel));
            }
        }

        public void Step(double delta, string sel = "")
        {
            // the place picked lifts its miniature; crossed swords bob over a battle
            _clock += delta;
            foreach (var idv in tiles)
            {
                string id = idv.AsString();
                GDict t = tiles[id].D;
                if (!t["node"].IsNull)
                {
                    Node3D n = t["node"].As<Node3D>();
                    double want = t["pos"].V3.y + (id == sel ? RAISE : 0.0);
                    { var np = n.Position; np.y = (float)GD.Lerpf(n.Position.y, want, GD.Minf(1.0, delta * 10.0)); n.Position = np; }
                }
                Sprite3D sw = t["swords"].As<Sprite3D>();
                if (sw.Visible)
                {
                    var sp = sw.Position;
                    sp.y = (float)(t["pos"].V3.y + SWORDS_UP + 0.08 * GD.Sin(_clock * 3.0));
                    sw.Position = sp;
                }
            }
        }
    }
}
