// Ported from godot/scripts/siege/rock_sculpt.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector2i = Fatebound.Sim.Vec2i;
using Vector3 = Fatebound.Sim.Vec3;
using Color = Fatebound.GUI.Col;

namespace Fatebound.Game
{
    using Land = Fatebound.Sim.Land;

    // The jungle's rock formations (0.31.216, Kevin: "need new models for grass and rock formations"; he chose them sculpted
    // in code): Honor of Kings' chunky blue-grey stone along each of the Rift's rock walls (siege_land.gd ridges(): the
    // sim's "rock" walls, the pits' rims too) -- boulders shouldered together along the wall's line, each a few big flat
    // facets with a mossy top, a slab or two at their feet. Built here once per run (seeded: the same every match), one
    // ArrayMesh per wall, drawn with rock_formation.gdshader (the painted rock texture from ElevenLabs, triplanar; moss
    // where a face turns up). The formations stand a little wider than the wall the sim keeps you out of, as a cliff's
    // foot does.
    //   COLOR: r = the boulder's tint (0..1), g = the height up the boulder (0 at its foot .. 1 at its top), b = 1 on the
    //   slabs at the feet (they take more moss)
    public class RockSculpt
    {
        public const int SEED = 216;
        public const double SINK = 0.35;                 // how far a boulder's foot sits in the ground
        public const double H_MIN = 2.3;                 // a wall boulder's height (a hero is ~1.8)
        public const double H_MAX = 3.3;
        public const double RIM_H_MIN = 1.2;             // the pits' rims are lower: you see the monster over them
        public const double RIM_H_MAX = 1.8;

        public static GArray _meshes = new GArray();     // [{mesh, aabb}] -- built once per run

        public static GArray Meshes()
        {
            if (_meshes.IsEmpty())
            {
                var rng = new Rng();
                rng.Seed = (ulong)SEED;
                foreach (var rg in Land.Ridges())
                {
                    if (GD.Str(rg.look) != "rock")
                        continue;
                    var m = _Wall(rg.pts, (double)rg.r, rg.pit >= 0, rng);
                    if (m != null)
                        _meshes.Append(Var.Of(m));
                }
            }
            return _meshes;
        }

        public static ArrayMesh _Wall(List<Vector2> pts, double r, bool rim, Rng rng)
        {
            var st = new SurfaceTool();
            st.Begin(Mesh.PRIMITIVE_TRIANGLES);
            // walk the wall's line: a boulder every so often, overlapping its neighbours
            var total = 0.0;
            for (int i = 0; i < pts.Count - 1; i++)
                total += pts[i].DistanceTo(pts[i + 1]);
            var step = GD.Maxf(1.2, r * (rim ? 1.25 : 1.55));
            var n = GD.Maxi(2, (int)Math.Ceiling(total / step) + 1);
            for (int k = 0; k < n; k++)
            {
                var s = total * (double)k / (double)(n - 1);
                var at = _Along(pts, s);
                Vector2 q = at[0].V2;
                Vector2 d = at[1].V2;
                var w = (2.0 * r + (rim ? 0.5 : 0.8)) * rng.RandfRange(0.85, 1.1);
                var l = w * rng.RandfRange(1.0, 1.35);
                double h = rim ? rng.RandfRange(RIM_H_MIN, RIM_H_MAX) : rng.RandfRange(H_MIN, H_MAX);
                if (!rim && (k == 0 || k == n - 1))
                    h *= 0.78;                                   // the ends step down
                var yaw = Math.Atan2(d.x, d.y) + rng.RandfRange(-0.35, 0.35);
                var off = new Vector2(-d.y, d.x) * rng.RandfRange(-0.25, 0.25) * r;
                _Boulder(st, q + off, l, w, h, yaw, rng.Randf(), rng, 0.0);
                // a slab or two at its feet, out to the sides
                foreach (double side in new[] { -1.0, 1.0 })
                {
                    if (rng.Randf() < (rim ? 0.35 : 0.55))
                    {
                        Vector2 sq = q + new Vector2(-d.y, d.x) * side * (w * 0.5 + rng.RandfRange(0.1, 0.6)) + d * rng.RandfRange(-0.8, 0.8);
                        double sw = rng.RandfRange(0.8, 1.5);
                        _Boulder(st, sq, sw * rng.RandfRange(1.0, 1.4), sw, rng.RandfRange(0.35, 0.7), rng.Randf() * GD.TAU, rng.Randf(), rng, 1.0);
                    }
                }
            }
            st.GenerateNormals();                              // (flat: every face has its own vertices -- the chunky facets)
            return st.Commit();
        }

        public static GArray _Along(List<Vector2> pts, double s)
        {
            // the point s metres along the polyline, and its direction there
            var acc = 0.0;
            for (int i = 0; i < pts.Count - 1; i++)
            {
                Vector2 a = pts[i];
                Vector2 b = pts[i + 1];
                double L = a.DistanceTo(b);
                if (acc + L >= s || i == pts.Count - 2)
                {
                    var t = GD.Clampf((s - acc) / GD.Maxf(L, 0.001), 0.0, 1.0);
                    return GArray.Of(a.Lerp(b, t), (b - a) / GD.Maxf(L, 0.001));
                }
                acc += L;
            }
            return GArray.Of(pts[0], new Vector2(0, 1));
        }

        public static GArray _ico = new GArray();          // [verts, faces] of a once-subdivided icosahedron (42 vertices, 80 faces)

        public static GArray _Icosphere()
        {
            if (!_ico.IsEmpty())
                return _ico;
            var t = (1.0 + Math.Sqrt(5.0)) / 2.0;
            GArray v = GArray.Of(new Vector3(-1, t, 0), new Vector3(1, t, 0), new Vector3(-1, -t, 0), new Vector3(1, -t, 0), new Vector3(0, -1, t), new Vector3(0, 1, t),
                new Vector3(0, -1, -t), new Vector3(0, 1, -t), new Vector3(t, 0, -1), new Vector3(t, 0, 1), new Vector3(-t, 0, -1), new Vector3(-t, 0, 1));
            for (int i = 0; i < v.Size(); i++)
                v[i] = v[i].V3.NormalizedChecked();
            GArray f = GArray.Of(GArray.Of(0, 11, 5), GArray.Of(0, 5, 1), GArray.Of(0, 1, 7), GArray.Of(0, 7, 10), GArray.Of(0, 10, 11), GArray.Of(1, 5, 9), GArray.Of(5, 11, 4), GArray.Of(11, 10, 2), GArray.Of(10, 7, 6),
                GArray.Of(7, 1, 8), GArray.Of(3, 9, 4), GArray.Of(3, 4, 2), GArray.Of(3, 2, 6), GArray.Of(3, 6, 8), GArray.Of(3, 8, 9), GArray.Of(4, 9, 5), GArray.Of(2, 4, 11), GArray.Of(6, 2, 10), GArray.Of(8, 6, 7), GArray.Of(9, 8, 1));
            var mids = new GDict();
            Func<int, int, int> mid = (int a, int b) =>
            {
                var key = new Vector2i(GD.Mini(a, b), GD.Maxi(a, b));
                if (mids.Has(key))
                    return (int)mids[key];
                v.Append((v[a].V3 + v[b].V3).NormalizedChecked());
                mids[key] = v.Size() - 1;
                return v.Size() - 1;
            };
            var f2 = new GArray();
            foreach (var tri in f)
            {
                int a = mid((int)tri[0], (int)tri[1]);
                int b = mid((int)tri[1], (int)tri[2]);
                int c = mid((int)tri[2], (int)tri[0]);
                f2.AppendArray(GArray.Of(GArray.Of(tri[0], a, c), GArray.Of(tri[1], b, a), GArray.Of(tri[2], c, b), GArray.Of(a, b, c)));
            }
            _ico = GArray.Of(v, f2);
            return _ico;
        }

        public static void _Boulder(SurfaceTool st, Vector2 at, double l, double w, double h, double yaw, double tint,
                Rng rng, double slab)
        {
            // A rounded block cut into big facets: the icosphere stretched to l x h x w, each vertex pushed in or out a little,
            // its top pressed flat into a plateau (the moss sits there) and its foot sunk into the ground.
            var ico = _Icosphere();
            GArray verts = ico[0].A;
            GArray faces = ico[1].A;
            var base_y = Land.TerrainHeight(at) - SINK;
            var basis = new Basis(Vector3.UP, yaw);
            var top = h * rng.RandfRange(0.72, 0.85);         // where the top starts to flatten
            var tilt = new Vector2(rng.RandfRange(-0.12, 0.12), rng.RandfRange(-0.12, 0.12));
            var jit = new GArray();
            for (int i = 0; i < verts.Size(); i++)
                jit.Append(rng.RandfRange(-0.13, 0.13));
            var pts = new GArray();
            for (int i = 0; i < verts.Size(); i++)
            {
                Vector3 u = verts[i].V3;
                var p = new Vector3(u.x * l * 0.5, (u.y * 0.5 + 0.5) * h, u.z * w * 0.5) * (1.0 + (double)jit[i]);
                if (p.y > top)
                    p.y = (float)(top + (p.y - top) * 0.45 + (double)tilt.x * p.x + (double)tilt.y * p.z);
                if (p.y < SINK * 0.5)
                    p.y = (float)(SINK * 0.5 + (p.y - SINK * 0.5) * 0.3);     // a flat-ish foot
                p.x = (float)(p.x * (1.0 + 0.18 * (1.0 - p.y / GD.Maxf(h, 0.01)) - 0.1));     // wider at the foot, narrower at the top
                p.z = (float)(p.z * (1.0 + 0.18 * (1.0 - p.y / GD.Maxf(h, 0.01)) - 0.1));
                pts.Append(basis * p + new Vector3(at.x, base_y, at.y));
            }
            var hi = top + 0.25 * (h - top);
            foreach (var tri in faces)
            {
                foreach (int k in new[] { 0, 2, 1 })                            // (the icosphere winds the other way round for Godot's front faces)
                {
                    Vector3 p = pts[(int)tri[k]].V3;
                    st.SetColor(new Color(tint, GD.Clampf((p.y - base_y) / GD.Maxf(hi, 0.01), 0.0, 1.0), slab));
                    st.AddVertex(p);
                }
            }
        }
    }
}
