// Ported from godot/scripts/siege/castle_kit.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector3 = Fatebound.Sim.Vec3;
using Color = Fatebound.GUI.Col;
using Transform3D = Fatebound.Sim.Xform3;
using AABB = Fatebound.Sim.Aabb;

namespace Fatebound.Game
{
    using Stage = Fatebound.Game.AssetCache;

    // Meshy castle kits (0.31.74). Kevin picked the concepts "A2" (Royal) and "B1" (War fortress) -- "B1 for one team and
    // A2 for the other" -- with "insides done also so the castles don't look cookie cutter" and "make sure players can climb
    // up on the front wall to shoot outside" (the rampart walkway behind the front wall, Castle.WALK_*, unchanged).
    //
    // Only what is DRAWN changes: the castle's layout (walls, gates, terraces, stairs, rooms) is the sim's, exactly as
    // before. Each piece is a Meshy model (assets/meshy/castle/, prepared by tools/meshy_building_tex.py: 1K texture, 512
    // for small props, fire glow masks), drawn with team_swap.gdshader so a kit's blue cloth turns red on the red castle.
    // The view (siege_view.gd, _build_castle*) lays the pieces along the sim's walls and terrace edges and puts the rest at
    // the spots below.
    public class CastleKit
    {
        public const string DIR = "res://assets/meshy/castle/";
        public static readonly Shader SWAP_SHADER = ResourceLoader.Load<Shader>("res://scripts/siege/team_swap.gdshader");
        // 0.31.75, Kevin: "make both castles the same royal style" -- both teams build the Royal kit; on the red castle
        // team_swap turns its blue roofs, banners and canopy red. The War kit stays described (and its files in the repo) but
        // is left out of the APK (export_presets.cfg, exclude_filter "assets/meshy/castle/war_*" and ".../floors/war_*"):
        // to bring it back, name it here AND drop those two patterns from the presets.
        public static readonly GArray STYLE_OF_TEAM = GArray.Of("royal", "royal");          // blue, red
        public static readonly Color FIRE_GLOW = new Color(1.0, 0.55, 0.18);

        // Per kit (sizes in metres; "model units" = the Meshy model's own, centred on its bounds):
        //   wall      curtain walls (the sim's "wall"/"backwall" lines): model, h (merlon tops), depth, len (piece length aimed for)
        //   terrace   terrace faces, stair sides and the rampart's edges: model, body (the part of its height below its balustrade
        //             or railing -- that part spans the climb), depth, len
        //   gatehouse round each gate: model, s (scale; its arch ~3 m wide), out (pushed out from the wall line, so the
        //             wall-walk behind stays clear), door (scale of the KayKit gate whose door leaves swing in the arch)
        //   tower     the four corner towers: model, s
        //   dungeon   archway over the doorway down to the dungeon: model, s, depth
        //   throne    behind / under the throne: model, s, ys (extra height factor), back (its middle, metres in front of the
        //             back wall's face), lift (metres the throne is raised: it stands on the war dais), sink (metres into the floor)
        //   floors    per area (court, walk, l1, l2, dungeon): [texture, metres per tile, tint]
        //   steps     the stairs' stone colour; treads (the striped tops) tinted by tread
        //   props     [model, castle-local spot (blue castle space: front wall z 3, back 29), level y, turn (deg; 0 = its front
        //             faces the castle's front), height] -- along walls and terrace edges, clear of the hat shops, stairs and
        //             the way to the dungeon (visual only, like the KayKit props before)
        //   fires     model -> flame points in model units (burning braziers, the forge, the dungeon gate's torches)
        public static readonly GDict KITS = new GDict
        {
            { "royal", new GDict
            {
                { "wall", GDict.Of("m", "royal_wall", "h", 2.9, "depth", 1.8, "len", 8.0) },
                { "terrace", GDict.Of("m", "royal_terrace_wall", "body", 0.70, "depth", 1.1, "len", 6.0) },
                { "gatehouse", GDict.Of("m", "royal_gatehouse", "s", 5.15, "out", 0.5, "door", 3.3) },
                { "tower", GDict.Of("m", "royal_tower", "s", 4.3) },
                { "dungeon", GDict.Of("m", "royal_dungeon_arch", "s", 4.3, "depth", 2.0) },
                { "throne", GDict.Of("m", "royal_throne_canopy", "s", 1.75, "ys", 1.0, "back", 0.35, "lift", 0.0) },
                { "floors", GDict.Of("court", GArray.Of("royal_court", 4.0, new Color(0.86, 0.84, 0.8)), "walk", GArray.Of("royal_court", 4.0, new Color(0.8, 0.78, 0.74)),
                    "l1", GArray.Of("royal_garden", 3.5, new Color(0.86, 0.86, 0.82)), "l2", GArray.Of("royal_marble", 4.0, new Color(0.9, 0.89, 0.87)),
                    "dungeon", GArray.Of("royal_court", 4.0, new Color(0.5, 0.5, 0.55))) },
                { "steps", Color.FromCode("#cbb994") }, { "tread", new Color(1.0, 0.97, 0.9) },
                { "props", GArray.Of(
                    GArray.Of("royal_fountain", new Vector2(-6.0, 12.75), 0.0, 0.0, 2.0),
                    GArray.Of("royal_stall", new Vector2(6.0, 12.55), 0.0, 0.0, 2.4),
                    GArray.Of("royal_topiary", new Vector2(-10.6, 4.9), 0.0, 0.0, 2.3),
                    GArray.Of("royal_topiary", new Vector2(10.6, 4.9), 0.0, 0.0, 2.3),
                    GArray.Of("royal_topiary", new Vector2(-5.9, 15.2), 1.8, 0.0, 2.1),
                    GArray.Of("royal_topiary", new Vector2(5.9, 15.2), 1.8, 0.0, 2.1),
                    GArray.Of("royal_hedge_box", new Vector2(-8.6, 20.9), 1.8, 0.0, 0.9),
                    GArray.Of("royal_hedge_box", new Vector2(-13.6, 20.9), 1.8, 0.0, 0.9),
                    GArray.Of("royal_hedge_box", new Vector2(8.6, 20.9), 1.8, 0.0, 0.9),
                    GArray.Of("royal_hedge_box", new Vector2(12.4, 20.9), 1.8, 0.0, 0.9),
                    GArray.Of("royal_topiary", new Vector2(-4.4, 23.2), 3.6, 0.0, 2.0),
                    GArray.Of("royal_topiary", new Vector2(4.4, 23.2), 3.6, 0.0, 2.0),
                    GArray.Of("royal_banner", new Vector2(-3.7, 25.8), 3.6, 0.0, 3.4),
                    GArray.Of("royal_banner", new Vector2(3.7, 25.8), 3.6, 0.0, 3.4),
                    GArray.Of("royal_statue", new Vector2(-6.0, 28.2), 3.6, 0.0, 2.6),
                    GArray.Of("royal_statue", new Vector2(6.0, 28.2), 3.6, 0.0, 2.6)
                ) },
                { "fires", new GDict() },
            } },
            { "war", new GDict
            {
                { "wall", GDict.Of("m", "war_wall", "h", 2.9, "depth", 1.8, "len", 8.0) },
                { "terrace", GDict.Of("m", "war_terrace_wall", "body", 0.76, "depth", 1.1, "len", 6.0) },
                { "gatehouse", GDict.Of("m", "war_gatehouse", "s", 4.4, "out", 0.8, "door", 3.0) },
                { "tower", GDict.Of("m", "war_tower", "s", 2.9) },
                { "dungeon", GDict.Of("m", "war_dungeon_gate", "s", 4.3, "depth", 2.0) },
                { "throne", GDict.Of("m", "war_throne_dais", "s", 1.9, "ys", 1.0, "back", 1.3, "lift", 0.16, "sink", 0.11) },
                { "floors", GDict.Of("court", GArray.Of("war_earth", 5.0, new Color(1, 1, 1)), "walk", GArray.Of("war_planks", 3.0, new Color(1, 1, 1)),
                    "l1", GArray.Of("war_planks", 3.0, new Color(1, 1, 1)), "l2", GArray.Of("war_slate", 4.0, new Color(1.1, 1.1, 1.1)),
                    "dungeon", GArray.Of("war_slate", 4.0, new Color(0.7, 0.7, 0.72))) },
                { "steps", Color.FromCode("#4a4e57") }, { "tread", new Color(0.55, 0.55, 0.6) },
                { "props", GArray.Of(
                    GArray.Of("war_forge", new Vector2(-6.0, 12.4), 0.0, 0.0, 2.6),
                    GArray.Of("war_weapon_rack", new Vector2(6.0, 12.9), 0.0, 0.0, 1.6),
                    GArray.Of("war_brazier", new Vector2(-10.1, 4.6), 0.0, 0.0, 1.4),
                    GArray.Of("war_brazier", new Vector2(10.1, 4.6), 0.0, 0.0, 1.4),
                    GArray.Of("war_dummy", new Vector2(-12.0, 5.0), 0.0, 20.0, 2.0),
                    GArray.Of("war_dummy", new Vector2(-12.3, 7.3), 0.0, -15.0, 2.0),
                    GArray.Of("war_dummy", new Vector2(12.0, 5.0), 0.0, -20.0, 2.0),
                    GArray.Of("war_brazier", new Vector2(-5.9, 15.2), 1.8, 0.0, 1.3),
                    GArray.Of("war_brazier", new Vector2(5.9, 15.2), 1.8, 0.0, 1.3),
                    GArray.Of("war_tent", new Vector2(-5.8, 20.4), 1.8, 0.0, 1.9),
                    GArray.Of("war_tent", new Vector2(9.4, 20.4), 1.8, 0.0, 1.9),
                    GArray.Of("war_tent", new Vector2(12.4, 20.4), 1.8, 0.0, 1.9),
                    GArray.Of("war_supplies", new Vector2(-18.6, 28.1), 3.6, 90.0, 1.2),
                    GArray.Of("war_supplies", new Vector2(11.0, 28.1), 3.6, -90.0, 1.2),
                    GArray.Of("war_weapon_rack", new Vector2(5.8, 28.4), 3.6, 0.0, 1.6),
                    GArray.Of("war_weapon_rack", new Vector2(-5.8, 28.4), 3.6, 0.0, 1.6)
                ) },
                { "fires", new GDict
                {
                    { "war_brazier", GArray.Of(new Vector3(0.0, 0.36, 0.01)) },
                    { "war_throne_dais", GArray.Of(new Vector3(0.766, -0.18, 0.617), new Vector3(-0.765, -0.18, 0.613)) },
                    { "war_forge", GArray.Of(new Vector3(-0.396, -0.37, -0.28)) },
                    { "war_dungeon_gate", GArray.Of(new Vector3(-0.739, 0.05, 0.14), new Vector3(0.748, 0.05, 0.13)) },
                } },
            } },
        };

        public static GDict _mats = new GDict();     // "model|team" -> ShaderMaterial

        public static GDict Kit(int team)
        {
            return KITS[STYLE_OF_TEAM[team]].D;
        }

        public static Node3D Piece(string model, int team)
        {
            // The model under a root whose origin is the middle of its foot (bottom of its bounds). Metas: "size" (its bounds,
            // model units), "lift" (model units -> root space offset, for points given in model units), "mat".
            var root = new Node3D();
            root.Name = model;
            PackedScene packed = Stage.Scene(DIR + model + ".glb");
            if (packed == null)
            {
                root.SetMeta("size", Vector3.ONE);
                root.SetMeta("lift", Vector3.ZERO);
                return root;
            }
            Node3D m = packed.Instantiate() as Node3D;
            var meshes = m.FindChildren("*", "MeshInstance3D", true, false);
            var box = new AABB();
            var first = true;
            foreach (var mi in meshes)
            {
                var xf = Transform3D.IDENTITY;
                Node n = mi;
                while (n != null && n != m)
                {
                    xf = (n as Node3D).Transform * xf;
                    n = n.GetParent();
                }
                AABB b = xf * (mi as MeshInstance3D).GetAabb();
                box = first ? b : box.Merge(b);
                first = false;
            }
            var c = box.GetCenter();
            m.Position = new Vector3(-c.x, -box.position.y, -c.z);
            root.AddChild(m);
            var mat = Material(model, team, meshes);
            foreach (var mi in meshes)
                (mi as MeshInstance3D).MaterialOverride = mat;
            root.SetMeta("size", box.size);
            root.SetMeta("lift", m.Position);
            root.SetMeta("mat", mat);
            return root;
        }

        public static ShaderMaterial Material(string model, int team, List<Node> meshes)
        {
            var key = GD.Fmt("%s|%d", model, team);
            if (_mats.Has(key))
                return _mats[key].As<ShaderMaterial>();
            var mat = new ShaderMaterial();
            mat.Shader = SWAP_SHADER;
            mat.SetShaderParameter("team", team);
            if (meshes.Count != 0)
            {
                var src = (meshes[0] as MeshInstance3D).GetActiveMaterial(0) as BaseMaterial3D;
                if (src != null)
                    mat.SetShaderParameter("albedo_tex", src.AlbedoTexture);
            }
            var glow_path = DIR + model + "_glow.png";
            var fiery = false;
            foreach (var k in KITS)
                fiery = fiery || KITS[k]["fires"].D.Has(model);
            if (fiery && Stage.Texture(glow_path) != null)
            {
                mat.SetShaderParameter("glow_tex", Stage.Texture(glow_path));
                mat.SetShaderParameter("glow_color", FIRE_GLOW);
                mat.SetShaderParameter("glow_energy", 1.0);
            }
            _mats[key] = Var.Of(mat);
            return mat;
        }

        public static bool LowerSideFlip(Vector2 a, Vector2 b, Func<Vector2, double> height_at)
        {
            // Terrace pieces show their decorated face (model +Z) to the LOWER side of the edge they line. With the run's
            // rotation (-atan2 of its direction) +Z points along (-d.y, d.x); true = turn it round.
            var d = (b - a).Normalized();
            var nrm = new Vector2(-d.y, d.x);
            var mid = (a + b) * 0.5;
            return (double)height_at(mid + nrm * 1.0) > (double)height_at(mid - nrm * 1.0) + 0.05;
        }
    }
}
