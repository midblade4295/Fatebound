// Ported from godot/scripts/siege/siege_view.gd (Fatebound 0.31.222): the Necromancer's plasma, fire baskets, edge
// scenery, the castle kits, the Rift's keeps, ridges and fords, the gates, rings and decals.
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector2i = Fatebound.Sim.Vec2i;
using Vector3 = Fatebound.Sim.Vec3;
using Vector4 = Fatebound.Sim.Vec4;
using Color = Fatebound.GUI.Col;
using Transform3D = Fatebound.Sim.Xform3;
using Quaternion = Fatebound.Sim.Quat;
using AABB = Fatebound.Sim.Aabb;
using Material = Fatebound.GUI.GMaterial;
using Environment = Fatebound.GUI.Environment;

namespace Fatebound.Game
{
    using Stage = Fatebound.Game.AssetCache;
    using Land = Fatebound.Sim.Land;
    using Keep = Fatebound.Sim.Keep;
    using Sim = Fatebound.Sim.SiegeSim;

    public partial class SiegeView
    {
        // ---------- the Necromancer's plasma siphon (0.31.50) ----------
        // Kevin: "a plasma beam" for the drain. Our own shader (plasma_beam.gdshader): a twisting plasma sheath round a hot core,
        // pulses running from the victim into the Necromancer, a soft glow at each end -- the victim's a darker, purple-green
        // wound, the Necromancer's a bright green bloom.
        public GDict plasma_nodes = new GDict();
        public static GDict _plasma_mats = new GDict();
        public static readonly Shader PLASMA_SHADER = ResourceLoader.Load<Shader>("res://scripts/siege/plasma_beam.gdshader");

        public static Material _PlasmaMat(string kind)
        {
            if (!_plasma_mats.Has(kind))
            {
                if (kind == "glow_src" || kind == "glow_dst")
                {
                    var gt = new GradientTexture2D();
                    gt.Fill = GradientTexture2D.FillEnum.Radial;
                    gt.FillFrom = new Vector2(0.5, 0.5);
                    gt.FillTo = new Vector2(1.0, 0.5);
                    var gr = new Gradient();
                    gr.SetColor(0, new Color(1, 1, 1, 1));
                    gr.SetColor(1, new Color(1, 1, 1, 0));
                    gr.AddPoint(0.35, new Color(1, 1, 1, 0.55));
                    gt.Gradient = gr;
                    var m = new StandardMaterial3D();
                    m.ShadingMode = BaseMaterial3D.SHADING_MODE_UNSHADED;
                    m.Transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;
                    m.BlendMode = BaseMaterial3D.BLEND_MODE_ADD;
                    m.BillboardMode = BaseMaterial3D.BILLBOARD_ENABLED;
                    m.NoDepthTest = false;
                    m.AlbedoTexture = gt;
                    m.AlbedoColor = kind == "glow_dst" ? new Color(0.3, 0.75, 0.35, 0.8) : new Color(0.45, 0.2, 0.75, 0.8);
                    _plasma_mats[kind] = Var.Of(m);
                }
                else
                {
                    var sm = new ShaderMaterial();
                    sm.Shader = PLASMA_SHADER;
                    sm.SetShaderParameter("core", kind == "core" ? 1.0 : 0.0);
                    sm.SetShaderParameter("intensity", kind == "core" ? 1.35 : 1.1);
                    sm.SetShaderParameter("twist", 3.0);
                    sm.SetShaderParameter("flow_dir", -1.0);     // 0.31.51 (Kevin): flowing back INTO the Necromancer (it ran out)
                    _plasma_mats[kind] = Var.Of(sm);
                }
            }
            return _plasma_mats[kind].As<Material>();
        }

        public Node3D _MakePlasma()
        {
            var root = new Node3D();
            foreach (var part in new (string, double, int)[] { ("sheath", 0.3, 18), ("core", 0.07, 8) })
            {
                var mi = new MeshInstance3D();
                var cm = new CylinderMesh();
                cm.TopRadius = part.Item2;
                cm.BottomRadius = part.Item2;
                cm.Height = 1.0;
                cm.RadialSegments = part.Item3;
                cm.Rings = 1;
                mi.Mesh = cm;
                mi.MaterialOverride = _PlasmaMat(part.Item1);
                mi.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
                mi.Name = part.Item1;
                root.AddChild(mi);
            }
            foreach (var g in new (string, double)[] { ("glow_src", 0.9), ("glow_dst", 1.1) })
            {
                var q = new MeshInstance3D();
                var qm = new QuadMesh();
                qm.Size = Vector2.ONE * g.Item2;
                q.Mesh = qm;
                q.MaterialOverride = _PlasmaMat(g.Item1);
                q.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
                q.Name = g.Item1;
                root.AddChild(q);
            }
            return root;
        }

        public void _SyncPlasma(string key, Unit u, Unit to)
        {
            // (to: the drained unit, null for the .gd's {})
            Node3D pb = plasma_nodes.Get(key).As<Node3D>();
            GDict a = actors.Get(u.id, new GDict()).D;
            GDict b = to != null ? actors.Get(to.id, new GDict()).D : new GDict();
            if (to == null || a.IsEmpty() || b.IsEmpty())
            {
                if (pb != null)
                    pb.Visible = false;
                return;
            }
            if (pb == null)
            {
                pb = _MakePlasma();
                AddChild(pb);
                plasma_nodes[key] = pb;
            }
            Vector3 p0 = a["root"].As<Node3D>().Position + new Vector3(0, 1.35, 0) + new Vector3(Math.Sin(u.face), 0, Math.Cos(u.face)) * 0.35;
            Vector3 p1 = b["root"].As<Node3D>().Position + new Vector3(0, 1.1, 0);
            var len = p0.DistanceTo(p1);
            if (len < 0.05)
            {
                pb.Visible = false;
                return;
            }
            pb.Visible = true;
            var up = (p1 - p0) / len;
            var side = up.Cross(Math.Abs(up.Dot(Vector3.FORWARD)) < 0.95 ? Vector3.FORWARD : Vector3.RIGHT).NormalizedChecked();
            var fwd = side.Cross(up);
            var mid = (p0 + p1) * 0.5;
            var h = (double)(GD.Hash(key) % 100);
            var wob = 1.0 + 0.14 * Math.Sin(_time * 13.0 + h) + 0.06 * Math.Sin(_time * 31.0 + h * 0.7);
            var sheath = pb.GetNode("sheath") as MeshInstance3D;
            var core = pb.GetNode("core") as MeshInstance3D;
            sheath.Transform = new Transform3D(new Basis(side * wob, up * len, fwd * wob), mid);
            core.Transform = new Transform3D(new Basis(side, up * len, fwd), mid);
            sheath.SetInstanceShaderParameter("beam_len", (double)len);
            core.SetInstanceShaderParameter("beam_len", (double)len);
            var g_src = pb.GetNode("glow_src") as Node3D;        // on the victim: the wound the plasma is pulled from
            var g_dst = pb.GetNode("glow_dst") as Node3D;        // at the Necromancer's hands
            g_src.Position = p1;
            g_dst.Position = p0;
            g_src.Scale = Vector3.ONE * (0.9 + 0.2 * Math.Sin(_time * 9.0 + h));
            g_dst.Scale = Vector3.ONE * (0.85 + 0.3 * Math.Pow(0.5 + 0.5 * Math.Sin(_time * 9.0 + h + 1.3), 3.0));
        }

        public GPUParticles3D _BeaconFire(Vector3 at)
        {
            // A fire basket's fire (the keep kit's braziers): soft additive flame puffs rising from the basket, shrinking as
            // they go; the ramp only shapes brightness and fade.
            var pm = new ParticleProcessMaterial();
            pm.EmissionShape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE;
            pm.EmissionSphereRadius = 0.45;
            pm.Direction = new Vector3(0, 1, 0);
            pm.Spread = 12.0;
            pm.InitialVelocityMin = 1.3;
            pm.InitialVelocityMax = 2.3;
            pm.Gravity = new Vector3(0.0, 1.2, 0.0) + SMOKE_WIND * 0.3;
            pm.DampingMin = 0.6;
            pm.DampingMax = 1.0;
            pm.ScaleMin = 0.7;
            pm.ScaleMax = 1.25;
            var sc = new Curve();
            sc.AddPoint(new Vector2(0.0, 0.7));
            sc.AddPoint(new Vector2(0.25, 1.0));
            sc.AddPoint(new Vector2(1.0, 0.15));
            var sct = new CurveTexture();
            sct.Curve = sc;
            pm.ScaleCurve = sct;
            var g = new Gradient();
            g.SetOffsets(new double[] { 0.0, 0.12, 0.55, 1.0 });                    // (g.offsets = ...: the property's setter)
            g.SetColors(new[] { new Color(1.25, 1.25, 1.25, 0.0), new Color(1.2, 1.2, 1.2, 1.0), new Color(0.9, 0.9, 0.9, 0.75),
                new Color(0.6, 0.6, 0.6, 0.0) });
            var gt = new GradientTexture1D();
            gt.Gradient = g;
            pm.ColorRamp = gt;
            var q = new QuadMesh();
            q.Size = new Vector2(0.75, 1.05);
            var m = new StandardMaterial3D();
            m.ShadingMode = BaseMaterial3D.SHADING_MODE_UNSHADED;
            m.Transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;      // mixed, not added: added flames wash out to white
            m.BillboardMode = BaseMaterial3D.BILLBOARD_PARTICLES;
            m.VertexColorUseAsAlbedo = true;
            m.AlbedoTexture = _SoftDot();
            q.Material = m;
            var p = new GPUParticles3D();
            p.ProcessMaterial = pm;
            p.DrawPass1 = q;
            p.Amount = 36;
            p.Lifetime = 0.8;
            p.Preprocess = 1.0;
            p.DrawOrder = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH;
            p.FixedFps = 30;
            p.Interpolate = true;
            p.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
            p.VisibilityAabb = new AABB(new Vector3(-2, -1, -2), new Vector3(4, 5, 4));
            if (low_fx)
                p.AmountRatio = 0.6;
            AddChild(p);
            p.GlobalPosition = at;
            return p;
        }

        public Node3D _Place(string path, Vector3 pos, double rot = 0.0, double s = 1.0)
        {
            var packed = Stage.Scene(path);
            if (packed == null)
                return null;
            Node3D node = packed.Instantiate() as Node3D;
            node.Position = pos;
            var r = node.Rotation;
            r.y = (float)rot;
            node.Rotation = r;
            node.Scale = Vector3.ONE * s;
            AddChild(node);
            return node;
        }

        public void _BuildEdgeScenery()
        {
            // Scenery beyond the field's edge (0.26.0): trees along the tops of the rock walls, none over
            // the cliff side or in the river's gorge; a few wooded hills further out.
            var rng = new Rng();
            rng.Seed = 21;
            var per = new GDict();                                   // (0.31.173: the Meshy trees, batched per kind; were KayKit trees, a node each)
            var loop = Land.EdgeLoop();
            for (int i = 0; i < loop.Count; i++)
            {
                Vector2 a = loop[i];
                Vector2 b = loop[(i + 1) % loop.Count];
                var L = a.DistanceTo(b);
                var nrm = new Vector2((b - a).y, -(b - a).x).Normalized();
                if (Land.InsideField((a + b) * 0.5 + nrm * 1.5))
                    nrm = -nrm;
                double t = rng.RandfRange(0.0, 2.0);
                while (t < L)
                {
                    var q = a.Lerp(b, t / L) + nrm * rng.RandfRange(3.5, 7.5);
                    if (Math.Abs(q.y - Land.RiverC(q.x)) > Land.RIVER_HW + 3.5 && !Land.InDungeonPit(q, 2.0))
                    {
                        var kind = Foliage.Pick(rng, Foliage.OUTER_TREES);
                        if (!per.Has(kind))
                            per[kind] = new GArray();
                        per[kind].A.Append(new Transform3D(new Basis(Vector3.UP, rng.Randf() * GD.TAU).Scaled(Vector3.ONE * (0.6 + rng.Randf() * 0.25)),
                            new Vector3(q.x, Land.TerrainHeight(q), q.y)));
                    }
                    t += rng.RandfRange(4.0, 6.5);
                }
            }
            foreach (var kind in per)
                _PlantBatch(kind.AsString(), per[kind].A, _Cast(), "edge_trees");
            foreach (var p in new[] { new Vector3(-Sim.HALF_W - 8, 0.5, -40), new Vector3(-Sim.HALF_W - 8, 0.5, 14), new Vector3(-Sim.HALF_W - 8, 0.5, -10),
                    new Vector3(Sim.HALF_W - 4, 0.5, 64), new Vector3(Sim.HALF_W - 4, 0.5, -64), new Vector3(0, 0.5, -Sim.HALF_L - 8), new Vector3(0, 0.5, Sim.HALF_L + 8) })
                _Place(HEX + "mountain_A_grass_trees.gltf", new Vector3(p.x, Land.TerrainHeight(new Vector2(p.x, p.z)) - 0.3, p.z), rng.Randf() * GD.TAU, 1.6);
        }

        public static readonly string[] COLOR = { "blue", "red" };
        public static GDict _floor_mats = new GDict();

        public void _WallRun(Vector2 a, Vector2 b, string path, double y = 0.0, bool clip = true, Vector2? inside_ = null)
        {
            Vector2 inside = inside_ ?? Vector2.INF;
            // inside (optional): a point inside what the wall encloses. The kit wall's stone face is its local +Z
            // (the other side has the walkway lip); pieces turn so the stone faces AWAY from it (Round 14,
            // Kevin: "the castle walls are backwards" -- the rotation came from the segment's direction, and
            // the red castle's mirrored walls run the other way; the model is centred, so turning doesn't shift it).
            // Lay 5.2 m wall models along a segment (clipped to the field unless told not to), stretched to fit.
            var aa = clip ? new Vector2(GD.Clampf(a.x, -Sim.HALF_W, Sim.HALF_W), GD.Clampf(a.y, -Sim.HALF_L, Sim.HALF_L)) : a;
            var bb = clip ? new Vector2(GD.Clampf(b.x, -Sim.HALF_W, Sim.HALF_W), GD.Clampf(b.y, -Sim.HALF_L, Sim.HALF_L)) : b;
            var length = aa.DistanceTo(bb);
            if (length < 0.5)
                return;
            var n = GD.Maxi(1, (int)GD.Round(length / Sim.SEG));
            var piece = length / (double)n;
            var rot = -Math.Atan2(bb.y - aa.y, bb.x - aa.x);
            if (inside != Vector2.INF)
            {
                var d = (bb - aa).Normalized();
                var stone = new Vector2(-d.y, d.x);                  // where local +Z points with this rotation
                if (stone.Dot((aa + bb) * 0.5 - inside) < 0.0)
                    rot += GD.PI;
            }
            for (int i = 0; i < n; i++)
            {
                var c = aa.Lerp(bb, ((double)i + 0.5) / (double)n);
                var node = _Place(path, new Vector3(c.x, y, c.y), rot, Sim.WALL_SCALE);
                if (node != null)
                {
                    var s = node.Scale;
                    s.x = (float)(Sim.WALL_SCALE * piece / Sim.SEG);
                    node.Scale = s;
                    _kit_nodes.Append(node);
                }
            }
        }

        public GArray _kit_nodes = new GArray();

        // ---------- Meshy castle kits (0.31.74, castle_kit.gd) ----------
        public Node3D _KitPiece(string model, int t, bool merge)
        {
            // One kit model (foot at its origin), added to the view. merge: baked into the castle's merged meshes with the
            // other copies of it (_merge_kit; the many wall pieces); otherwise a node of its own (keeps its LODs).
            var root = CastleKit.Piece(model, Vt(t));
            AddChild(root);
            if (merge)
                _kit_nodes.Append(root);
            else
            {
                foreach (var mi in root.FindChildren("*", "MeshInstance3D", true, false))
                {
                    (mi as MeshInstance3D).CastShadow = _Cast();
                    mi.SetMeta("perf", "castle");
                }
            }
            return root;
        }

        public void _KitWallRun(int t, Vector2 a, Vector2 b, double y, bool clip, Vector2 inside)
        {
            // The kit's curtain wall along a sim wall line -- as _wall_run (same clipping, decorated face away from inside),
            // in pieces of about the kit's length, stretched to fit.
            if (_kit_skip)
                return;
            GDict k = CastleKit.Kit(t)["wall"].D;
            var aa = clip ? new Vector2(GD.Clampf(a.x, -Sim.HALF_W, Sim.HALF_W), GD.Clampf(a.y, -Sim.HALF_L, Sim.HALF_L)) : a;
            var bb = clip ? new Vector2(GD.Clampf(b.x, -Sim.HALF_W, Sim.HALF_W), GD.Clampf(b.y, -Sim.HALF_L, Sim.HALF_L)) : b;
            var length = aa.DistanceTo(bb);
            if (length < 0.5)
                return;
            var n = GD.Maxi(1, (int)GD.Round(length / (double)k["len"]));
            var piece = length / (double)n;
            var rot = -Math.Atan2(bb.y - aa.y, bb.x - aa.x);
            if (inside != Vector2.INF)
            {
                var d = (bb - aa).Normalized();
                if (new Vector2(-d.y, d.x).Dot((aa + bb) * 0.5 - inside) < 0.0)
                    rot += GD.PI;
            }
            for (int i = 0; i < n; i++)
            {
                var c = aa.Lerp(bb, ((double)i + 0.5) / (double)n);
                var root = _KitPiece(GD.Str(k["m"]), t, true);
                Vector3 size = Var.Of(root.GetMeta("size")).AsVec3();
                root.Position = new Vector3(c.x, y, c.y);
                var r = root.Rotation;
                r.y = (float)rot;
                root.Rotation = r;
                root.Scale = new Vector3(piece / size.x, (double)k["h"] / size.y, (double)k["depth"] / size.z);
            }
        }

        public void _KitFire(Node3D root, Vector3 model_pt, Vector3 _size)
        {
            // A small flame at a point given in the model's own units (a brazier's bowl, the forge, a torch).
            var at = root.ToGlobal(model_pt + Var.Of(root.GetMeta("lift")).AsVec3());
            var s = root.Scale.x;
            var f = _BeaconFire(at);
            f.Scale = Vector3.ONE * GD.Clampf(s * 0.22, 0.22, 0.5);
            ((f.DrawPass1 as QuadMesh).Material as StandardMaterial3D).AlbedoColor = new Color(1.5, 0.62, 0.18, 0.8);
            f.Amount = 14;
        }

        public static GDict _kit_merged = new GDict();      // team -> [[material, merged mesh], ...]: a castle's walls, kept for rematches
        public bool _kit_skip = false;                      // building a castle whose merged walls are cached: the pieces aren't made

        public void _MergeKit(int team = -1)
        {
            // All KayKit hex models share one atlas material: bake every static castle piece (walls,
            // terrace walls, towers, buildings, props, banners, trees) into ONE mesh per material instead
            // of ~70 separate draw calls per castle. Animated pieces (gates, catapults) and the hat stands
            // stay separate. 0.31.78: the merged meshes of a kit castle are kept (per team) for the next match of the session,
            // which then skips the ~40 wall pieces and the merge (~80 ms a castle here).
            if (team >= 0 && _kit_merged.Has(team))
            {
                foreach (var pair in _kit_merged[team])
                {
                    var mi = new MeshInstance3D();
                    mi.Mesh = pair[1].As<Mesh>();
                    mi.MaterialOverride = pair[0].As<Material>();
                    mi.CastShadow = _Cast();
                    mi.SetMeta("perf", "castle");
                    AddChild(mi);
                }
                _kit_nodes.Clear();
                _kit_skip = false;
                return;
            }
            var tools = new GDict();
            foreach (var n in _kit_nodes)
            {
                if (n.IsNull || !GD.IsInstanceValid(n))
                    continue;
                foreach (var mi in n.As<Node>().FindChildren("*", "MeshInstance3D", true, false))
                {
                    var m3 = mi as MeshInstance3D;
                    Transform3D xf = GlobalTransform.AffineInverse() * m3.GlobalTransform;
                    for (int si = 0; si < m3.Mesh.GetSurfaceCount(); si++)
                    {
                        Material mat = m3.GetActiveMaterial(si);
                        if (!tools.Has(Var.Of(mat)))
                        {
                            var st = new SurfaceTool();
                            st.Begin(Mesh.PRIMITIVE_TRIANGLES);
                            tools[Var.Of(mat)] = Var.Of(st);
                        }
                        tools[Var.Of(mat)].As<SurfaceTool>().AppendFrom(m3.Mesh, si, xf);
                    }
                }
                n.As<Node>().QueueFree();
            }
            _kit_nodes.Clear();
            var merged = new GArray();
            foreach (var mat in tools)
            {
                var mi = new MeshInstance3D();
                mi.Mesh = tools[mat].As<SurfaceTool>().Commit();
                mi.MaterialOverride = mat.As<Material>();
                mi.CastShadow = _Cast();
                mi.SetMeta("perf", "castle");
                AddChild(mi);
                merged.Append(GArray.Of(mat, Var.Of(mi.Mesh)));
            }
            if (team >= 0 && CASTLE_KITS)
                _kit_merged[team] = merged;
            _kit_skip = false;
        }

        // ---------- 0.31.165: the Rift's keeps (keep.gd), ridges and fords (siege_land.gd) ----------
        public void _BuildKeep(int t)
        {
            // A keep: its paved floor; the kit's curtain wall along the sim's ring (so collision and visuals agree), a tower on
            // every third joint; a gatehouse with doors at each gate (they swing open for the keep's own side, break into
            // rubble -- the gates are League's inhibitors); the throne with the kit's canopy behind it and a carpet down to the
            // middle gate; the fountain at the back where heroes come back.
            GDict kit = CastleKit.Kit(t);
            var face = t == 0 ? 0.0 : GD.PI;
            Vector2 cen = Sim.M(t, Keep.C);
            _kit_skip = CASTLE_KITS && _kit_merged.Has(t);
            _KeepFloor(t, cen);
            foreach (var w in sim.walls)
            {
                if (w.team == t && w.kind == "wall")
                {
                    // (a little longer than the chord: the pieces overlap at the joints, no wedge of sky between them)
                    Vector2 d = (w.b - w.a).Normalized();
                    _KitWallRun(t, w.a - d * 0.4, w.b + d * 0.4, 0.0, false, cen);
                }
            }
            GDict tk = kit["tower"].D;
            var joints = Keep.Joints();
            for (int k = 0; k < joints.Count; k++)
            {
                if (k % 3 != 0)
                    continue;
                Vector2 jp = Sim.M(t, joints[k]);
                Vector2 out0 = (jp - cen).Normalized();
                var tw = _KitPiece(GD.Str(tk["m"]), t, false);
                tw.Position = new Vector3(jp.x, 0.0, jp.y);
                var tr = tw.Rotation;
                tr.y = (float)Math.Atan2(out0.x, out0.y);
                tw.Rotation = tr;
                tw.Scale = Vector3.ONE * (double)tk["s"];
            }
            GDict gk = kit["gatehouse"].D;
            var big = Keep.GATEHOUSE_K;
            foreach (var g in sim.gates)
            {
                if (g.team != t)
                    continue;
                Vector2 @out = -g.@in;
                var rot = Math.Atan2(@out.x, @out.y);                   // local +Z (the stone face) outwards
                var node = _Place(HEX + "wall_straight_gate.gltf", new Vector3(g.c.x, 0, g.c.y), rot, Sim.WALL_SCALE);
                var gh = _KitPiece(GD.Str(gk["m"]), t, false);
                Vector2 gp = g.c + @out * (double)gk["out"];
                gh.Position = new Vector3(gp.x, 0.0, gp.y);
                var ghr = gh.Rotation;
                ghr.y = (float)rot;
                gh.Rotation = ghr;
                gh.Scale = Vector3.ONE * (double)gk["s"] * big;
                node.Scale = Vector3.ONE * (double)gk["door"] * big;
                foreach (var mi in node.FindChildren("*", "MeshInstance3D", true, false))
                {
                    if (!GD.Str(mi.Name).Contains("door"))
                        (mi as MeshInstance3D).Mesh = null;          // its wall piece (the doors are its children: hiding it hid them)
                }
                var doors = new GArray();
                foreach (var mi in node.FindChildren("*door*", "MeshInstance3D", true, false))
                    doors.Append(GDict.Of("node", mi, "sign", GD.Str(mi.Name).Contains("left") ? 1.0 : -1.0));
                var rubble = new Node3D();
                rubble.Position = new Vector3(g.c.x, 0, g.c.y);
                AddChild(rubble);
                var along = new Vector2(@out.y, -@out.x);
                for (int i = 0; i < 3; i++)
                {
                    Vector2 rp = g.c + along * (i - 1) * 1.1 + @out * GD.RandfRange(-0.3, 0.3);
                    var r = _Place(HEX + new[] { "rock_single_D.gltf", "rock_single_E.gltf", "crate_open.gltf" }[i],
                        new Vector3(rp.x, 0, rp.y), GD.Randf() * GD.TAU, new[] { 3.2, 3.2, 1.7 }[i]);
                    if (r != null)
                        r.Reparent3D(rubble, true);                 // (reparent(rubble, true): the facade's Node3D reparent keeping the global transform)
                }
                rubble.Visible = false;
                gate_nodes[g.id] = GDict.Of("doors", doors, "rubble", rubble, "open", 0.0, "broken", false);
            }
            // the throne: the kit's canopy behind it, the Blender throne (velvet in the side's colour), a carpet to the gate
            GDict thk = kit["throne"].D;
            Vector2 tp = Sim.M(t, Keep.THRONE_SEAT);
            var cpiece = _KitPiece(GD.Str(thk["m"]), t, false);
            Vector3 csize = Var.Of(cpiece.GetMeta("size")).AsVec3();
            var s3 = (double)thk["s"];
            Vector2 bp = Sim.M(t, Keep.THRONE_SEAT + new Vector2(0.0, 0.55));
            cpiece.Position = new Vector3(bp.x, -(double)thk.Get("sink", 0.0), bp.y);
            var cr = cpiece.Rotation;
            cr.y = (float)(face + GD.PI);
            cpiece.Rotation = cr;
            cpiece.Scale = new Vector3(s3, s3 * (double)thk["ys"], s3);
            foreach (var fp in kit["fires"].D.Get(GD.Str(thk["m"]), new GArray()))
                _KitFire(cpiece, fp.AsVec3(), csize);
            var throne = _Place("res://assets/props/throne.glb", new Vector3(tp.x, (double)thk["lift"], tp.y), t == 0 ? GD.PI : 0.0, 1.0);
            if (throne != null)
            {
                var velvet = new StandardMaterial3D();
                velvet.AlbedoColor = Vt(t) == 0 ? new Color("#2d58b8") : new Color("#b3223a");
                velvet.Roughness = 0.85;
                foreach (var mi in throne.FindChildren("*", "MeshInstance3D", true, false))
                {
                    MeshInstance3D m = mi as MeshInstance3D;
                    for (int si = 0; si < m.Mesh.GetSurfaceCount(); si++)
                    {
                        var sm = m.Mesh.SurfaceGetMaterial(si);
                        if (sm != null && GD.Str(sm.ResourceName) == "Velvet")
                            m.SetSurfaceOverrideMaterial(si, velvet);
                    }
                }
            }
            _Carpet(Sim.M(t, Keep.KING + new Vector2(0.0, 1.2)), Sim.M(t, Keep.GateC(1) + new Vector2(0.0, 1.6)), 2.6,
                Vt(t) == 0 ? new Color("#2f5f8a") : new Color("#8a3a2f"));
            Vector2 th = Sim.Throne(t);
            _Decal(new Vector3(th.x, 0.06, th.y), 2.2, TEAM_COLORS[Vt(t)], 0.6);            // (the old throne's reach)
            // the fountain: the kit's fountain on a round dais, a ring of light round where heroes come back and heal
            Vector2 fpos = Sim.M(t, Keep.FOUNTAIN);
            _KeepProp(t, Keep.FOUNTAIN_MODEL, Keep.FOUNTAIN, 0.0, 2.2);
            _Decal(new Vector3(fpos.x, 0.07, fpos.y), Keep.FOUNTAIN_R + 0.2, TEAM_COLORS[Vt(t)], 0.55);
            // a few of the kit's props against the back of the wall (clear of the fighting in the middle)
            foreach (var pr in Keep.PROPS)
                _KeepProp(t, GD.Str(pr.model), pr.p, pr.turn, pr.h);
        }

        public Node3D _KeepProp(int t, string model, Vector2 spot, double turn_deg, double height)
        {
            // a kit prop at a spot in blue's keep (world coordinates, mirrored for red): turn 0 = its front faces the keep's front
            var root = _KitPiece(model, t, false);
            Vector3 size = Var.Of(root.GetMeta("size")).AsVec3();
            Vector2 p = Sim.M(t, spot);
            root.Position = new Vector3(p.x, 0.0, p.y);
            var r = root.Rotation;
            r.y = (float)((t == 0 ? 0.0 : GD.PI) + GD.PI + GD.DegToRad(turn_deg));
            root.Rotation = r;
            root.Scale = Vector3.ONE * (height / size.y);
            foreach (var fp in CastleKit.Kit(t)["fires"].D.Get(model, new GArray()))
                _KitFire(root, fp.AsVec3(), size);
            return root;
        }

        public static GDict _keep_floor_mats = new GDict();
        public const double KEEP_PAVE_M = 6.0;

        public void _KeepFloor(int t, Vector2 cen)
        {
            // the kit's courtyard paving over the whole keep (under the wall's foot), the cloud shadows drifting over it too
            if (!_keep_floor_mats.Has(t))
            {
                // 0.31.216: the royal paving ElevenLabs painted (tools/ground_paint.py: cream and gold sandstone, carved tiles here
                // and there), KEEP_PAVE_M metres a tile; the castle kit's court floor until then
                Texture2D tex = Stage.Texture(PAINT + "keep.webp");
                var tint = new Color(0.9, 0.88, 0.86);
                var uv = FLOOR_TILE / KEEP_PAVE_M;
                if (_cast_static)
                    _keep_floor_mats[t] = Var.Of(_CloudFloorMaterial(tex, tint, uv));
                else
                {
                    var fm = new StandardMaterial3D();
                    fm.AlbedoTexture = tex;
                    fm.AlbedoColor = tint;
                    fm.Uv1Scale = new Vector3(uv, uv, 1.0);
                    fm.Roughness = 0.95;
                    fm.SpecularMode = BaseMaterial3D.SPECULAR_DISABLED;
                    _keep_floor_mats[t] = Var.Of(fm);
                }
            }
            var n = 48;
            var rad = Keep.R + 0.6;
            var verts = new List<Vector3>();
            var uvs = new List<Vector2>();
            var norms = new List<Vector3>();
            var idx = new List<int>();
            verts.Add(new Vector3(cen.x, 0.03, cen.y));
            uvs.Add(cen / FLOOR_TILE);
            norms.Add(Vector3.UP);
            for (int k = 0; k < n; k++)
            {
                var q = cen + Vector2.FromAngle(GD.TAU * k / n) * rad;
                verts.Add(new Vector3(q.x, 0.03, q.y));
                uvs.Add(q / FLOOR_TILE);
                norms.Add(Vector3.UP);
            }
            for (int k = 0; k < n; k++)
                idx.AddRange(new[] { 0, 1 + k, 1 + (k + 1) % n });        // (clockwise seen from above: the front)
            var arr = new GArray();
            arr.Resize(Mesh.ARRAY_MAX);
            arr[Mesh.ARRAY_VERTEX] = Var.Of(verts);
            arr[Mesh.ARRAY_TEX_UV] = Var.Of(uvs);
            arr[Mesh.ARRAY_NORMAL] = Var.Of(norms);
            arr[Mesh.ARRAY_INDEX] = Var.Of(idx);
            var am = new ArrayMesh();
            am.AddSurfaceFromArrays(Mesh.PRIMITIVE_TRIANGLES, arr);
            var mi = new MeshInstance3D();
            mi.Mesh = am;
            mi.MaterialOverride = _keep_floor_mats[t].As<Material>();
            mi.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
            mi.SetMeta("perf", "castle");
            AddChild(mi);
        }

        public void _Carpet(Vector2 a, Vector2 b, double w, Color color)
        {
            var key = color.ToHtmlExact();
            if (!_floor_mats.Has(key))
            {
                var m = new StandardMaterial3D();
                m.AlbedoColor = color;
                m.Roughness = 0.95;
                _floor_mats[key] = Var.Of(m);
            }
            var pm = new PlaneMesh();
            pm.Size = new Vector2(w, a.DistanceTo(b));
            var mi = new MeshInstance3D();
            mi.Mesh = pm;
            mi.MaterialOverride = _floor_mats[key].As<Material>();
            mi.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
            var c = (a + b) * 0.5;
            mi.Position = new Vector3(c.x, 0.05, c.y);
            var r = mi.Rotation;
            r.y = (float)Math.Atan2(b.x - a.x, b.y - a.y);
            mi.Rotation = r;
            AddChild(mi);
        }

        public static readonly string[] RIDGE_ROCKS = { "Rock_1_D_Color1", "Rock_1_E_Color1", "Rock_1_F_Color1" };
        public static readonly string[] RIDGE_SMALL = { "Rock_1_A_Color1", "Rock_1_B_Color1", "Rock_1_C_Color1" };
        public static GDict _ridge_plan = new GDict();       // model -> Array[Transform3D], built once per session

        public static GDict _PlanRidges()
        {
            // Along each of the Rift's ridges (Land.ridges(): the sim's "rock" walls): boulders shouldered together along the
            // line with smaller stones at their feet, or a stand of trees with bushes under them. Seeded: the same every match.
            var rng = new Rng();
            rng.Seed = 165;
            var output = new GDict();
            var keys = new GArray();
            foreach (var k in RIDGE_ROCKS)
                keys.Append(k);
            foreach (var k in RIDGE_SMALL)
                keys.Append(k);
            keys.AppendArray(Foliage.RIDGE_TREES.Keys());
            keys.AppendArray(Foliage.RIDGE_BUSHES.Keys());
            foreach (var k in keys)
                output[k] = new GArray();
            foreach (var rg in Land.Ridges())
            {
                List<Vector2> pts = rg.pts;
                var r = rg.r;
                bool trees = GD.Str(rg.look) == "trees";
                for (int i = 0; i < pts.Count - 1; i++)
                {
                    Vector2 a = pts[i];
                    Vector2 b = pts[i + 1];
                    var L = a.DistanceTo(b);
                    var d = (b - a) / L;
                    var nrm = new Vector2(-d.y, d.x);
                    double t = i == 0 ? 0.0 : rng.RandfRange(0.4, 0.9);
                    while (t <= L + 0.01)
                    {
                        var q = a + d * t + nrm * rng.RandfRange(-0.35, 0.35) * r;
                        var y = Land.TerrainHeight(q) - 0.15;
                        if (trees)
                        {
                            // (0.31.173: the Meshy trees and bushes of foliage.gd; were KayKit's)
                            var s = rng.RandfRange(0.78, 0.98);
                            output[Foliage.Pick(rng, Foliage.RIDGE_TREES)].Append(
                                new Transform3D(new Basis(Vector3.UP, rng.Randf() * GD.TAU).Scaled(Vector3.ONE * s), new Vector3(q.x, y, q.y)));
                            foreach (var side in new[] { -1.0, 1.0 })
                            {
                                if (rng.Randf() < 0.7)
                                {
                                    Vector2 bq = q + nrm * side * (r + rng.RandfRange(-0.2, 0.3)) + d * rng.RandfRange(-0.6, 0.6);
                                    var bs = rng.RandfRange(1.3, 1.9);
                                    output[Foliage.Pick(rng, Foliage.RIDGE_BUSHES)].Append(new Transform3D(new Basis(Vector3.UP, rng.Randf() * GD.TAU).Scaled(
                                        Vector3.ONE * bs), new Vector3(bq.x, Land.GroundHeight(bq) - 0.05, bq.y)));          // (ground_height(bq, false))
                                }
                            }
                            t += rng.RandfRange(1.8, 2.4);
                        }
                        else if (!SCULPTED_ROCKS)
                        {
                            var s2 = (2.0 * r + 0.4) * rng.RandfRange(0.95, 1.2);
                            var sy = rng.RandfRange(0.75, 1.05);
                            output[RIDGE_ROCKS[(int)(rng.Randi() % (uint)RIDGE_ROCKS.Length)]].Append(new Transform3D(
                                new Basis(Vector3.UP, rng.Randf() * GD.TAU).Scaled(new Vector3(s2, s2 * sy, s2)), new Vector3(q.x, y - 0.25, q.y)));
                            foreach (var side in new[] { -1.0, 1.0 })
                            {
                                if (rng.Randf() < 0.45)
                                {
                                    Vector2 sq = q + nrm * side * (r + rng.RandfRange(0.0, 0.4)) + d * rng.RandfRange(-0.7, 0.7);
                                    var ss = rng.RandfRange(0.9, 1.6);
                                    output[RIDGE_SMALL[(int)(rng.Randi() % (uint)RIDGE_SMALL.Length)]].Append(new Transform3D(
                                        new Basis(Vector3.UP, rng.Randf() * GD.TAU).Scaled(Vector3.ONE * ss), new Vector3(sq.x, Land.GroundHeight(sq) - 0.08, sq.y)));
                                }
                            }
                            t += rng.RandfRange(1.1, 1.5) * r;
                        }
                        else
                            break;                                  // (0.31.216: rock_sculpt.gd builds the rock walls)
                    }
                }
            }
            return output;
        }

        // 0.31.216 (Kevin: "need new models for grass and rock formations"; sculpted in code): the rock walls and the pits'
        // rims are Honor of Kings' chunky blue-grey formations (rock_sculpt.gd, rock_formation.gdshader), not KayKit's rocks
        public const bool SCULPTED_ROCKS = true;
        public static ShaderMaterial _rock_mat = null;

        public static ShaderMaterial _RockMaterial()
        {
            if (_rock_mat == null)
            {
                _rock_mat = new ShaderMaterial();
                _rock_mat.Shader = ResourceLoader.Load<Shader>("res://scripts/siege/rock_formation.gdshader");
                _rock_mat.SetShaderParameter("rock_tex", Stage.Texture(PAINT + "rock.webp"));
                _rock_mat.SetShaderParameter("moss_tex", Stage.Texture(PAINT + "grass.webp"));
                _rock_mat.SetShaderParameter("macro_tex", _TerrainMaterial().GetShaderParameter("macro_tex"));
                _rock_mat.SetShaderParameter("tint", PAINT_TINT * 1.12);
            }
            return _rock_mat;
        }

        public void _BuildRidges()
        {
            // One MultiMesh per model and 32 m band (off-screen bands are culled); they cast shadows like the keeps do.
            if (SCULPTED_ROCKS)
            {
                foreach (var m in RockSculpt.Meshes())
                {
                    var mi = new MeshInstance3D();
                    mi.Mesh = m.As<Mesh>();
                    mi.MaterialOverride = _RockMaterial();
                    mi.CastShadow = _Cast();
                    mi.SetMeta("perf", "ridges");
                    mi.SetMeta("perf_kind", "sculpted");
                    AddChild(mi);
                }
            }
            if (_ridge_plan.IsEmpty())
                _ridge_plan = _PlanRidges();
            foreach (var kind in _ridge_plan)
            {
                GArray xfs = _ridge_plan[kind].A;
                if (xfs.IsEmpty())
                    continue;
                if (Foliage.IsPlant(GD.Str(kind)))
                {
                    // (0.31.173) a Meshy tree or bush: trees cast shadows, bushes don't
                    _PlantBatch(GD.Str(kind), xfs, GD.Str(kind).BeginsWith("tree") ? _Cast() : GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "ridges");
                    continue;
                }
                var packed = Stage.Scene(FOREST + GD.Str(kind) + ".gltf");
                if (packed == null)
                    continue;
                Node3D node = packed.Instantiate() as Node3D;
                MeshInstance3D src = node.FindChildren("*", "MeshInstance3D", true, false)[0] as MeshInstance3D;
                var bands = new GDict();
                foreach (var xf in xfs)
                {
                    var bkey = (int)Math.Floor((((Transform3D)xf).origin.z + Sim.HALF_L) / 32.0);
                    if (!bands.Has(bkey))
                        bands[bkey] = new GArray();
                    bands[bkey].Append(xf);
                }
                foreach (var bkey in bands)
                {
                    var mm = new MultiMesh();
                    mm.TransformFormat = MultiMesh.TRANSFORM_3D;
                    mm.Mesh = src.Mesh;
                    mm.InstanceCount = bands[bkey].Size();
                    for (int i = 0; i < mm.InstanceCount; i++)
                        mm.SetInstanceTransform(i, (Transform3D)bands[bkey][i] * src.Transform);
                    var mmi = new MultiMeshInstance3D();
                    mmi.Multimesh = mm;
                    mmi.CastShadow = _Cast();
                    mmi.SetMeta("perf", "ridges");
                    mmi.SetMeta("perf_kind", GD.Str(kind));
                    AddChild(mmi);
                }
                node.Free();
            }
        }

        public const double PLANT_CELL = 16.0;

        public void _PlantBatch(string kind, GArray xfs, ShadowCastingSetting shadow, string perf, double cell = PLANT_CELL)
        {
            // 0.31.173: a Meshy tree or bush (foliage.gd) at these places -- one MultiMesh per PLANT_CELL square: the portrait
            // view sees a strip a fraction of the field's width, so whole-width bands drew ~3x the plants on screen, and a
            // small cell's distance lets the far ones take the engine's lighter LODs (only where the difference is under a pixel).
            // A tree's shadow is drawn from its shadow copy (Foliage.shadow_of: the same model remeshed by Meshy, its canopy just
            // inside the tree's own -- tools/foliage_prep.py --shadow) in a shadow-only MultiMesh; the tree itself casts none:
            // a third of the triangles in the shadow pass for the same shadow on the ground.
            var tm = Foliage.Mesh(kind);
            if (tm == null)
                return;
            var sk = shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF ? Foliage.ShadowOf(kind) : "";
            Mesh sm = sk != "" ? Foliage.Mesh(sk) : null;
            var cells = new GDict();
            foreach (var xf in xfs)
            {
                Vector3 o = ((Transform3D)xf).origin;
                var ckey = new Vector2i((int)Math.Floor(o.x / cell), (int)Math.Floor(o.z / cell));
                if (!cells.Has(ckey))
                    cells[ckey] = new GArray();
                cells[ckey].Append(xf);
            }
            foreach (var ckeyv in cells)
            {
                Vector2i ckey = ckeyv.AsVec2i();
                var mmi = _PlantMm(tm, cells[ckey].A, Foliage.Material(kind), sm != null ? GeometryInstance3D.SHADOW_CASTING_SETTING_OFF : shadow);
                mmi.SetMeta("perf", perf);
                mmi.SetMeta("perf_kind", kind);
                mmi.SetMeta("places", cells[ckey].A);          // (the instances' transforms live in the renderer: tests read them here)
                mmi.Name = GD.Fmt("%s_%s_%d_%d", perf == "brush" ? "Brush" : "Plants", kind, ckey.x, ckey.y);     // (tests and the bench find the brush by name)
                AddChild(mmi);
                if (sm != null)
                {
                    var smi = _PlantMm(sm, cells[ckey].A, Foliage.Material(sk), GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY);
                    smi.SetMeta("perf", perf + "_shadow");
                    smi.SetMeta("perf_kind", sk);
                    smi.Name = GD.Fmt("Shadows_%s_%d_%d", kind, ckey.x, ckey.y);
                    AddChild(smi);
                }
            }
        }

        public static MultiMeshInstance3D _PlantMm(Mesh m, GArray xfs, Material mat, ShadowCastingSetting shadow)
        {
            var mm = new MultiMesh();
            mm.TransformFormat = MultiMesh.TRANSFORM_3D;
            mm.Mesh = m;
            mm.InstanceCount = xfs.Size();
            for (int i = 0; i < mm.InstanceCount; i++)
                mm.SetInstanceTransform(i, (Transform3D)xfs[i]);
            var mmi = new MultiMeshInstance3D();
            mmi.Multimesh = mm;
            mmi.MaterialOverride = mat;
            mmi.CastShadow = shadow;
            return mmi;
        }

        public void _BuildFords()
        {
            // The fords' stepping stones: flat stones across each (Land.FORDS), a little proud of the water, in staggered rows.
            var rng = new Rng();
            rng.Seed = 166;
            var src = _MeshOf(FOREST + "Rock_1_E_Color1.gltf");
            if (src.IsEmpty())
                return;
            var xfs = new GArray();
            foreach (var f in Land.FORDS)
            {
                var fx = f[0];
                var hw = f[1];
                if (Math.Abs(fx) < 1.0 || Math.Abs(Math.Abs(fx) - Land.SIDE_CORNER_X) < 1.0)
                    continue;                               // (0.31.216: a lane's ford is its paving, laid through the water)
                var c = Land.RiverC(fx);
                var reach = Land.RiverHw(fx) + 0.6;
                var y = c - reach;
                var row = 0;
                while (y <= c + reach)
                {
                    var x = fx - hw + (row % 2 == 1 ? 0.55 : 0.0) + rng.RandfRange(0.0, 0.3);
                    while (x <= fx + hw)
                    {
                        var q = new Vector2(x, y + rng.RandfRange(-0.15, 0.15));
                        if (Land.Shore(q) < 0.4 && Land.IslandOff(q) > 0.2)
                        {
                            var s = rng.RandfRange(0.7, 0.95);
                            xfs.Append(new Transform3D(new Basis(Vector3.UP, rng.Randf() * GD.TAU).Scaled(new Vector3(s, 0.16, s)),
                                new Vector3(q.x, Land.FORD_Y - 0.12, q.y)));
                        }
                        x += rng.RandfRange(1.1, 1.4);
                    }
                    y += 1.15;
                    row += 1;
                }
            }
            var mm = new MultiMesh();
            mm.TransformFormat = MultiMesh.TRANSFORM_3D;
            mm.Mesh = src["mesh"].As<Mesh>();
            mm.InstanceCount = xfs.Size();
            for (int i = 0; i < xfs.Size(); i++)
                mm.SetInstanceTransform(i, (Transform3D)xfs[i]);
            var mmi = new MultiMeshInstance3D();
            mmi.Multimesh = mm;
            mmi.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
            var sm = new StandardMaterial3D();                   // pale, water-worn stone (the forest rocks' grey read as a dark cobble patch)
            sm.AlbedoColor = new Color("#8d949a");             // (0.31.216: the lanes' grey-blue slabs; #b9b2a2 until then)
            sm.Roughness = 0.9;
            mmi.MaterialOverride = sm;
            mmi.SetMeta("perf", "fords");
            AddChild(mmi);
        }

        public void _SyncCastle(double dt)
        {
            _SyncBeams();
            _SyncShields();
            _SyncWhirls();
            foreach (var g in sim.gates)
            {
                GDict gn = gate_nodes.Get(g.id, new GDict()).D;
                if (gn.IsEmpty())
                    continue;
                bool broken = g.broken || g.hp <= 0.0;      // (0.31.217: an open gate isn't a broken one)
                // (0.31.78: transforms and visibility are set only when they change -- a closed gate's doors were re-posed every
                // frame, every tree re-scaled, every stockpile piece re-shown: each a transform update for the renderer)
                if (broken != (bool)gn["broken"])
                {
                    gn["broken"] = broken;
                    gn["rubble"].As<Node3D>().Visible = broken;
                    foreach (var d in gn["doors"])
                        d["node"].As<Node3D>().Visible = !broken;
                }
                var want = (g.open || sim.open_gates) && !broken ? 1.0 : 0.0;
                var was = (double)gn["open"];
                gn["open"] = GD.MoveToward(was, want, dt * 2.5);
                if ((double)gn["open"] != was)
                {
                    foreach (var d in gn["doors"])
                    {
                        var dn = d["node"].As<Node3D>();
                        var r = dn.Rotation;
                        r.y = (float)((double)d["sign"] * (double)gn["open"] * GD.PI * 0.5);
                        dn.Rotation = r;
                    }
                }
            }
            for (int t = 0; t < 2; t++)
            {
                GDict o_node = t < oracle_nodes.Size() ? oracle_nodes[t].D : new GDict();
                if (!o_node.IsEmpty() && !o_node["body"].IsNull)
                {
                    Node3D body = o_node["body"].As<Node3D>();
                    var breathe = 1.0 + 0.018 * Math.Sin(_time * 2.4 + t);
                    body.Scale = new Vector3(2.0 - breathe, breathe, 2.0 - breathe);
                    body.Rotation = new Vector3(0.0, 0.08 * Math.Sin(_time * 0.9 + t * 2.0), 0.035 * Math.Sin(_time * 1.3 + t));
                }
            }
        }

        public StandardMaterial3D _Unshaded(Color color, bool additive = true)
        {
            var m = new StandardMaterial3D();
            m.ShadingMode = BaseMaterial3D.SHADING_MODE_UNSHADED;
            m.Transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;
            if (additive)
                m.BlendMode = BaseMaterial3D.BLEND_MODE_ADD;
            m.AlbedoColor = color;
            m.CullMode = BaseMaterial3D.CULL_DISABLED;
            m.NoDepthTest = false;
            return m;
        }

        public TorusMesh _RingMesh(double radius, double width = 0.14)
        {
            var key = GD.Fmt("%.2f:%.2f", radius, width);
            if (_rings.Has(key))
                return _rings[key].As<TorusMesh>();
            var tm = new TorusMesh();
            tm.InnerRadius = radius - width;
            tm.OuterRadius = radius;
            tm.Rings = 32;
            tm.RingSegments = 4;
            _rings[key] = Var.Of(tm);
            return tm;
        }

        public MeshInstance3D _Decal(Vector3 pos, double radius, Color color, double alpha)
        {
            var mi = new MeshInstance3D();
            mi.Mesh = _RingMesh(radius, 0.18);
            mi.Scale = new Vector3(1, 0.15, 1);
            var c = color;
            c.a = (float)alpha;
            mi.MaterialOverride = _Unshaded(c);
            mi.CastShadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;
            mi.Position = pos;
            AddChild(mi);
            return mi;
        }
    }
}
