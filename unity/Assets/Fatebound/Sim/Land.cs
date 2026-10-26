// The Rift (siege_land.gd, 0.31.216): Honor of Kings' square -- blue's keep in the bottom-left corner and red's in the
// top-right seen from the yawed landscape camera; in world coordinates a diamond with the keeps at the ends of the y
// axis, the middle lane straight down it, the river across it along x. Pure static data + functions: the sim turns it
// into walls / nav / heights, the view into terrain. Defined for blue's half (+y) and point-mirrored for red.
using System;
using System.Collections.Generic;

namespace Fatebound.Sim
{
    public sealed class Ridge
    {
        public List<Vec2> pts;
        public double r;
        public string look;
        public int pit = -1;
    }

    public static class Land
    {
        public const double HOK_HALF = 78.0;
        public const double HOK_L = HOK_HALF * 1.4142135;
        public const double HALF_W = 111.0;
        public const double HALF_L = 110.0;

        static Vec2 V(double x, double y) => new Vec2(x, y);

        // ---------------- the lanes ----------------
        public static readonly Vec2[][] LANES =
        {
            new[] { V(-9.9, 86.13), V(-19.73, 76.3), V(-33.87, 62.15), V(-48.01, 48.01), V(-62.15, 33.87),
                V(-76.3, 19.73), V(-83.3, 12.73), V(-87.2, 6.89), V(-88.57, 0.0), V(-87.2, -6.89),
                V(-83.3, -12.73), V(-76.3, -19.73), V(-62.15, -33.87), V(-48.01, -48.01), V(-33.87, -62.15),
                V(-19.73, -76.3), V(-9.9, -86.13) },
            new[] { V(0.0, 82.02), V(0.0, 56.57), V(0.0, 28.28), V(0.0, 0.0), V(0.0, -28.28),
                V(0.0, -56.57), V(0.0, -82.02) },
            new[] { V(9.9, 86.13), V(19.73, 76.3), V(33.87, 62.15), V(48.01, 48.01), V(62.15, 33.87),
                V(76.3, 19.73), V(83.3, 12.73), V(87.2, 6.89), V(88.57, 0.0), V(87.2, -6.89),
                V(83.3, -12.73), V(76.3, -19.73), V(62.15, -33.87), V(48.01, -48.01), V(33.87, -62.15),
                V(19.73, -76.3), V(9.9, -86.13) },
        };

        // ---------------- the river, its fords and the pits ----------------
        public const double RIVER_AMP = 0.0;
        public const double RIVER_K = 0.07;
        public const double RIVER_HW = 4.5;
        public const double RIVER_WANDER = 0.9;
        public const double POOL_X = 42.0;
        public const double POOL_EXTRA = 7.5;
        public const double POOL_SIGMA = 9.0;
        public const double LAKE_EXTRA = POOL_EXTRA;
        public const double PIT_R = 7.0;
        public const double PIT_WALL_R = 0.8;
        public const double PIT_MOUTH = 2.6;
        public const double WATER_Y = -0.45;
        public const double BED_Y = -0.58;
        public const double FORD_Y = -0.4;
        public const double SIDE_CORNER_X = 88.57;
        public static readonly double[][] FORDS =
            { new[] { 0.0, 3.4 }, new[] { SIDE_CORNER_X, 3.4 }, new[] { -SIDE_CORNER_X, 3.4 }, new[] { POOL_X, PIT_MOUTH }, new[] { -POOL_X, PIT_MOUTH } };

        public static double RiverC(double x) => RIVER_AMP * Math.Sin(RIVER_K * x);

        public static double RiverHw(double x)
        {
            double d = Math.Abs(x) - POOL_X;
            return RIVER_HW + RIVER_WANDER * Math.Cos(0.13 * x) * Math.Cos(0.051 * x + 0.4 * Math.Sin(0.21 * x))
                + POOL_EXTRA * Math.Exp(-(d / POOL_SIGMA) * (d / POOL_SIGMA));
        }

        public static double RiverOff(Vec2 p) => Math.Abs(p.y - RiverC(p.x)) - RiverHw(p.x);

        public static Vec2 PitC(int i)
        {
            double x = i == 0 ? -POOL_X : POOL_X;
            return new Vec2(x, RiverC(x));
        }

        public static double IslandOff(Vec2 p) => Math.Min((double)p.DistanceTo(PitC(0)), (double)p.DistanceTo(PitC(1))) - PIT_R;

        public static double Shore(Vec2 p) => GD.Max(RiverOff(p), -IslandOff(p));

        public static bool OnFord(Vec2 p, double margin = 0.0)
        {
            if (RiverOff(p) > 1.0) return false;
            foreach (var f in FORDS)
                if (Math.Abs(p.x - f[0]) <= f[1] + margin) return true;
            return false;
        }

        // ---------------- the field's edge ----------------
        public static readonly Vec2[] EDGE_BLUE =
        {
            V(101.31, 9.0), V(86.31, 24.0), V(70.31, 40.0), V(54.31, 56.0), V(38.31, 72.0),
            V(24.31, 86.0), V(15.0, 95.3), V(14.28, 101.2), V(9.77, 107.64), V(3.93, 110.68),
            V(0.0, 111.2), V(-3.93, 110.68), V(-9.77, 107.64), V(-14.28, 101.2), V(-15.0, 95.3),
            V(-24.31, 86.0), V(-38.31, 72.0), V(-54.31, 56.0), V(-70.31, 40.0), V(-86.31, 24.0),
            V(-101.31, 9.0), V(-108.81, 1.5),
        };
        public const double EDGE_R = 0.6;
        public static readonly int[] EDGE_SKIP = { 6, 7, 8, 9, 10, 11, 12, 13 };

        static List<Vec2> _loop;
        public static List<Vec2> EdgeLoop()
        {
            if (_loop == null)
            {
                var l = new List<Vec2>();
                foreach (var q in EDGE_BLUE) l.Add(q);
                foreach (var q in EDGE_BLUE) l.Add(-q);
                _loop = l;
            }
            return _loop;
        }

        public static bool InsideField(Vec2 p)
        {
            if (Math.Abs(p.x) > HALF_W || Math.Abs(p.y) > HALF_L) return false;
            return Geometry2D.IsPointInPolygon(p, EdgeLoop());
        }

        public static double EdgeDist(Vec2 p)
        {
            if (Math.Abs(p.x) + Math.Abs(p.y) < HOK_L - 16.0) return -8.0;
            var lp = EdgeLoop();
            double best = GD.INF;
            for (int i = 0; i < lp.Count; i++)
            {
                Vec2 a = lp[i];
                Vec2 b = lp[(i + 1) % lp.Count];
                Vec2 ab = b - a;
                double t = GD.Clamp((p - a).Dot(ab) / GD.Max(ab.LengthSquared(), 0.0001), 0.0, 1.0);
                best = GD.Min(best, p.DistanceTo(a + ab * t));
            }
            return Geometry2D.IsPointInPolygon(p, lp) ? -best : best;
        }

        public const double RISE_H = 6.5;

        // ---------------- the jungle's rock ridges and tree lines ----------------
        static Ridge Rg(double r, string look, params Vec2[] pts) => new Ridge { pts = new List<Vec2>(pts), r = r, look = look };

        public static readonly Ridge[] RIDGES_BLUE =
        {
            Rg(1.7, "rock", V(-41.7, 26.5), V(-39.8, 30.15), V(-36.54, 32.65), V(-32.53, 33.54), V(-28.51, 32.65)),
            Rg(1.5, "rock", V(-41.01, 46.67), V(-33.23, 48.79), V(-26.87, 46.67)),
            Rg(1.4, "trees", V(-19.1, 56.05), V(-15.21, 54.64), V(-12.55, 51.46), V(-11.83, 47.39)),
            Rg(1.5, "rock", V(-8.49, 28.28), V(-9.9, 21.21), V(-14.85, 16.26)),
            Rg(1.4, "trees", V(-64.82, 11.12), V(-66.47, 14.42), V(-66.47, 18.11), V(-64.82, 21.41)),
            Rg(1.7, "rock", V(41.7, 26.5), V(39.8, 30.15), V(36.54, 32.65), V(32.53, 33.54), V(28.51, 32.65)),
            Rg(1.5, "rock", V(41.01, 46.67), V(33.23, 48.79), V(26.87, 46.67)),
            Rg(1.4, "trees", V(19.1, 56.05), V(15.21, 54.64), V(12.55, 51.46), V(11.83, 47.39)),
            Rg(1.5, "rock", V(8.49, 28.28), V(9.9, 21.21), V(14.85, 16.26)),
            Rg(1.4, "trees", V(64.82, 11.12), V(66.47, 14.42), V(66.47, 18.11), V(64.82, 21.41)),
        };
        public const string PIT_ROCK_LOOK = "rock";

        static List<Ridge> _ridges;
        /// <summary>Both halves, and the pits' rims.</summary>
        public static List<Ridge> Ridges()
        {
            if (_ridges != null) return _ridges;
            var outl = new List<Ridge>();
            foreach (var rg in RIDGES_BLUE)
            {
                outl.Add(rg);
                var m = new List<Vec2>();
                foreach (var q in rg.pts) m.Add(-q);
                outl.Add(new Ridge { pts = m, r = rg.r, look = rg.look });
            }
            for (int i = 0; i < 2; i++)
            {
                foreach (double side in new[] { 1.0, -1.0 })
                {
                    Vec2 c = PitC(i);
                    double da = Math.Asin(PIT_MOUTH / PIT_R) + 0.12;
                    double a0 = side > 0.0 ? Math.PI * 0.5 + da : -Math.PI * 0.5 + da;
                    double a1 = a0 + Math.PI - 2.0 * da;
                    var pts = new List<Vec2>();
                    int n = 6;
                    for (int k = 0; k < n + 1; k++)
                    {
                        double a = GD.Lerp(a0, a1, (double)k / n);
                        pts.Add(c + new Vec2(Math.Cos(a), Math.Sin(a)) * PIT_R);
                    }
                    outl.Add(new Ridge { pts = pts, r = PIT_WALL_R, look = PIT_ROCK_LOOK, pit = i });
                }
            }
            _ridges = outl;
            return _ridges;
        }

        /// <summary>(distance to the nearest ridge's line, its half-thickness) -- as a Vector2, float.</summary>
        public static Vec2 RidgeDist(Vec2 p)
        {
            double best = GD.INF;
            double br = 0.0;
            foreach (var rg in Ridges())
            {
                var pts = rg.pts;
                for (int i = 0; i < pts.Count - 1; i++)
                {
                    Vec2 a = pts[i];
                    Vec2 b = pts[i + 1];
                    if (p.DistanceTo(a) > a.DistanceTo(b) + 6.0) continue;
                    Vec2 ab = b - a;
                    double t = GD.Clamp((p - a).Dot(ab) / GD.Max(ab.LengthSquared(), 0.0001), 0.0, 1.0);
                    double d = p.DistanceTo(a + ab * t);
                    if (d < best)
                    {
                        best = d;
                        br = rg.r;
                    }
                }
            }
            return new Vec2(best, br);
        }

        // ---------------- dirt paths (visual) ----------------
        public static readonly Vec2[][] TRAILS_BLUE =
        {
            new[] { V(-31.75, 60.03), V(-25.46, 53.74), V(-19.8, 48.08), V(-12.73, 41.01), V(-2.83, 36.77), V(2.83, 31.11) },
            new[] { V(-19.8, 48.08), V(-18.38, 32.53), V(-32.53, 24.04) },
            new[] { V(-32.53, 24.04), V(-25.46, 16.97), V(-14.14, 11.31), V(-1.41, 7.07) },
            new[] { V(-61.45, 30.33), V(-59.4, 22.63), V(-58.69, 16.26), V(-49.99, 15.49), V(-44.05, 13.51), V(-42.07, 12.66) },
            new[] { V(-32.53, 24.04), V(-42.43, 19.8), V(-52.33, 18.38), V(-58.69, 16.26) },
            new[] { V(31.75, 60.03), V(25.46, 53.74), V(19.8, 48.08), V(12.73, 41.01), V(2.83, 36.77), V(-2.83, 31.11) },
            new[] { V(19.8, 48.08), V(18.38, 32.53), V(32.53, 24.04) },
            new[] { V(32.53, 24.04), V(25.46, 16.97), V(14.14, 11.31), V(1.41, 7.07) },
            new[] { V(61.45, 30.33), V(59.4, 22.63), V(58.69, 16.26), V(49.99, 15.49), V(44.05, 13.51), V(42.07, 12.66) },
            new[] { V(32.53, 24.04), V(42.43, 19.8), V(52.33, 18.38), V(58.69, 16.26) },
        };
        public const double PATH_HALF_W = 2.1;
        public const double TRAIL_HALF = 1.3;
        public const double PATH_STEP = 0.75;
        public const double PATH_FADE = 3.2;
        public const double PATH_CORE = 0.5;
        static List<List<Vec2>> _paths, _trails;

        public static List<List<Vec2>> Paths()
        {
            if (_paths != null) return _paths;
            var o = new List<List<Vec2>>();
            foreach (var pl in LANES) o.Add(SmoothLine(pl));
            _paths = o;
            return o;
        }

        public static List<List<Vec2>> Trails()
        {
            if (_trails != null) return _trails;
            var o = new List<List<Vec2>>();
            foreach (var pl in TRAILS_BLUE)
            {
                var sm = SmoothLine(pl);
                o.Add(sm);
                var m = new List<Vec2>();
                foreach (var q in sm) m.Add(-q);
                o.Add(m);
            }
            _trails = o;
            return o;
        }

        public static List<Vec2> SmoothLine(IReadOnlyList<Vec2> pl)
        {
            var o = new List<Vec2> { pl[0] };
            for (int i = 0; i < pl.Count - 1; i++)
            {
                Vec2 p0 = pl[Math.Max(i - 1, 0)];
                Vec2 p1 = pl[i];
                Vec2 p2 = pl[i + 1];
                Vec2 p3 = pl[Math.Min(i + 2, pl.Count - 1)];
                int n = Math.Max(1, (int)Math.Ceiling(p1.DistanceTo(p2) / PATH_STEP));
                for (int k = 1; k < n + 1; k++) o.Add(p1.CubicInterpolate(p2, p0, p3, (double)k / n));
            }
            return o;
        }

        public static double PathWobble(Vec2 p)
        {
            double slow = 0.32 * Math.Cos(0.21 * p.x + 0.17 * p.y) * Math.Cos(0.13 * p.x - 0.19 * p.y);
            double rag = 0.20 * Math.Cos(1.3 * p.x + 0.9 * p.y) + 0.13 * Math.Cos(2.3 * p.x - 1.9 * p.y) + 0.08 * Math.Sin(3.7 * p.x) * Math.Sin(4.1 * p.y);
            return slow + rag;
        }

        public const double APRON_BLEND = 2.2;
        public const double PIT_APRON_IN = 3.0;

        public static double SmoothMin(double a, double b, double k)
        {
            if (double.IsPositiveInfinity(a)) return b;
            if (double.IsPositiveInfinity(b)) return a;
            double h = GD.Clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
            return GD.Lerp(b, a, h) - k * h * (1.0 - h);
        }

        public static double GroundDist(Vec2 p, double dPath)
        {
            double best = dPath;
            for (int i = 0; i < 2; i++) best = SmoothMin(best, GD.Max(0.0, p.DistanceTo(PitC(i)) - (PIT_R - PIT_APRON_IN)), APRON_BLEND);
            return best;
        }

        public const double LANE_PAVE_HALF = 2.9;

        public static double LanePave(double d, Vec2 p)
        {
            double a = 1.0 - GD.Clamp((d - 0.5 * PathWobble(p) - LANE_PAVE_HALF + 0.5) / 1.0, 0.0, 1.0);
            return a * Smooth(Keep.R + 0.6, Keep.R + 2.6, KeepDist(p));
        }

        public static double DistToLanes(Vec2 p)
        {
            double best = GD.INF;
            foreach (var pl in Paths()) best = GD.Min(best, DistLine(p, pl));
            return best;
        }

        public static double PathR(double d, Vec2 p) => 1.0 - GD.Clamp((d - PathWobble(p) - PATH_CORE) / PATH_FADE, 0.0, 1.0);

        public static double DistToPaths(Vec2 p)
        {
            double best = GD.INF;
            foreach (var pl in Paths()) best = GD.Min(best, DistLine(p, pl));
            foreach (var pl in Trails()) best = GD.Min(best, DistLine(p, pl) + PATH_HALF_W - TRAIL_HALF);
            return best;
        }

        static double DistLine(Vec2 p, List<Vec2> pl)
        {
            double best = GD.INF;
            for (int i = 0; i < pl.Count - 1; i++)
            {
                Vec2 a = pl[i];
                Vec2 b = pl[i + 1];
                Vec2 ab = b - a;
                double t = GD.Clamp((p - a).Dot(ab) / GD.Max(ab.LengthSquared(), 0.0001), 0.0, 1.0);
                best = GD.Min(best, p.DistanceTo(a + ab * t));
            }
            return best;
        }

        // ---------------- heights ----------------
        public static double Smooth(double e0, double e1, double x)
        {
            double t = GD.Clamp((x - e0) / (e1 - e0), 0.0, 1.0);
            return t * t * (3.0 - 2.0 * t);
        }

        public static double Wobble(Vec2 p) =>
            0.5 * Math.Cos(0.9 * p.x + 0.7 * p.y) + 0.3 * Math.Cos(2.1 * p.x - 1.7 * p.y) + 0.2 * Math.Sin(1.3 * p.x) * Math.Sin(2.9 * p.y);

        public static double EdgeJit(Vec2 p) =>
            EdgeDist(p) + 0.9 * (0.6 * Math.Sin(0.37 * p.x + 1.1) * Math.Sin(0.41 * p.y + 0.3) + 0.4 * Math.Sin(1.13 * p.x - 0.9 * p.y));

        public static double KeepDist(Vec2 p)
        {
            Vec2 q = p.y >= 0.0f ? p : -p;
            return q.DistanceTo(Keep.C);
        }

        public static double Rolling(Vec2 p)
        {
            double h = 0.42 * Math.Sin(0.19 * p.x) * Math.Sin(0.23 * p.y) + 0.32 * Math.Cos(0.13 * p.x) * Math.Cos(0.11 * p.y);
            double fade = Smooth(Keep.ZONE, Keep.ZONE + 8.0, KeepDist(p));
            fade *= Smooth(1.5, 6.0, RiverOff(p));
            return h * fade;
        }

        /// <summary>Where units stand. Inside the keeps: level.</summary>
        public static double GroundHeight(Vec2 p)
        {
            if (KeepDist(p) < Keep.ZONE) return 0.0;
            double sh = Shore(p);
            if (sh < 0.8)
            {
                double bed = GD.Lerp(BED_Y, 0.0, Smooth(-0.6, 0.8, sh));
                if (OnFord(p)) bed = GD.Max(bed, FORD_Y);
                return bed;
            }
            return Rolling(p);
        }

        /// <summary>(rim, shadow) for the terrain mask.</summary>
        public static Vec2 LedgeRim(Vec2 p)
        {
            double rim = 0.0, shadow = 0.0;
            Vec2 rd = RidgeDist(p);
            if (rd.x < rd.y + 2.5)
            {
                double ragged = 0.35 * Wobble(p * 1.7);
                rim = 1.0 - Smooth(rd.y * 0.6, rd.y + 0.9 + ragged, rd.x);
                shadow = (1.0 - Smooth(rd.y + 0.2, rd.y + 2.2, rd.x)) * 0.55;
            }
            double ed = EdgeJit(p);
            if (ed > -3.0)
            {
                double face = Smooth(-0.4, 0.4, ed) * (1.0 - Smooth(3.2, 4.4, ed));
                double patches = Smooth(0.35, 0.8, 0.5 + 0.5 * Math.Sin(0.53 * p.x + 0.2) * Math.Sin(0.47 * p.y + 1.7)) * Smooth(3.0, 5.0, ed) * 0.7;
                rim = GD.Max(rim, GD.Max(face, patches));
                shadow = GD.Max(shadow, (1.0 - Smooth(0.0, 2.2, -ed)) * 0.8);
            }
            return new Vec2(GD.Clamp(rim, 0.0, 1.0), GD.Clamp(shadow, 0.0, 1.0));
        }

        // ---------------- baked terrain (visual) ----------------
        public const double BAKE_MARGIN = 7.0;
        public const double BAKE_STEP = 1.0;
        public const double MASK_PPM = 4.0;
        public const double RIDGE_H = 1.1;

        public static bool InDungeonPit(Vec2 p, double margin = 0.0) => false;

        public static double TerrainHeight(Vec2 p)
        {
            Vec2 inside = new Vec2(GD.Clamp(p.x, -HALF_W - 1.5, HALF_W + 1.5), GD.Clamp(p.y, -HALF_L, HALF_L));
            double h = GroundHeight(inside);
            if (EdgeDist(p) <= 0.0)
            {
                Vec2 rd = RidgeDist(p);
                if (rd.x < rd.y + 0.6)
                    h += RIDGE_H * (1.0 - Smooth(rd.y * 0.3, rd.y + 0.6, rd.x)) * (0.75 + 0.25 * Wobble(p * 0.9));
                return h;
            }
            double ed = GD.Max(EdgeJit(p), 0.0);
            double hi = RISE_H * (0.85 + 0.3 * Math.Sin(0.21 * p.x + 0.5) * Math.Sin(0.17 * p.y + 1.1));
            double rise = hi * (0.55 * Smooth(0.0, 1.6, ed) + 0.45 * Smooth(2.2, 3.6, ed))
                + 1.3 * Smooth(4.0, 10.0, ed) * (0.5 + 0.5 * Math.Sin(0.41 * p.x + 0.7) * Math.Sin(0.33 * p.y + 1.3));
            double top = GD.Max(h, 0.0);
            double outv = top + rise;
            outv = GD.Lerp(BED_Y, outv, Smooth(-0.4, 2.8, RiverOff(p)));
            return outv;
        }

        public const double BAND_W = 5.0;
        public static readonly Vec2[] BAND_CENTRES = { V(-60.0, 40.0), V(60.0, 10.0), V(-14.0, 118.0), V(56.0, 80.0) };

        public static double GrassBand(Vec2 p)
        {
            Vec2 q = p + new Vec2(1.3 * Math.Sin(0.13 * p.y + 0.4), 1.3 * Math.Cos(0.11 * p.x + 1.1));
            double d1 = GD.INF, d2 = GD.INF;
            foreach (var c in BAND_CENTRES)
            {
                foreach (var cc in new[] { c, -c })
                {
                    double d = q.DistanceTo(cc);
                    if (d < d1) { d2 = d1; d1 = d; }
                    else if (d < d2) d2 = d;
                }
            }
            double Ring(double d) => Smooth(0.32, 0.68, 0.5 + 0.5 * Math.Sin(GD.TAU * d / BAND_W));
            double t = Smooth(-2.0, 2.0, d2 - d1);
            return GD.Lerp(0.5 * (Ring(d1) + Ring(d2)), Ring(d1), t);
        }

        // ---------------- the world beyond the playfield (view only) ----------------
        public const double OUTER_REACH = 260.0;

        public static double OuterHeight(Vec2 p)
        {
            double rx0 = -HALF_W - BAKE_MARGIN, ry0 = -HALF_L - BAKE_MARGIN;
            double rx1 = HALF_W + BAKE_MARGIN, ry1 = HALF_L + BAKE_MARGIN;
            Vec2 q = new Vec2(GD.Clamp(p.x, rx0, rx1), GD.Clamp(p.y, ry0, ry1));
            double d = p.DistanceTo(q);
            double hills = 1.2 * Math.Sin(p.x * 0.07 + 1.3) * Math.Sin(p.y * 0.055 + 0.4) + 0.9 * Math.Sin(p.x * 0.031 - p.y * 0.043 + 2.0);
            double rise = GD.Clamp((d - 5.0) / 28.0, 0.0, 1.0);
            double h = RISE_H + hills * (0.6 + 4.0 * rise) + rise * rise * 7.0;
            double mtn = GD.Smoothstep(40.0, 130.0, d);
            h += mtn * (28.0 + 14.0 * Math.Sin(p.x * 0.021 + 0.7) * Math.Sin(p.y * 0.017 + 1.9) + 8.0 * Math.Sin(p.x * 0.05 + p.y * 0.037));
            h = GD.Lerp(TerrainHeight(q), h, GD.Smoothstep(0.0, 14.0, d));
            if (d > 0.0)
            {
                double off = Math.Abs(p.y - RiverC(p.x));
                h = GD.Lerp(WATER_Y - 0.7, h, GD.Smoothstep(RIVER_HW - 0.5, RIVER_HW + 6.0 + d * 0.32, off));
            }
            return h;
        }

        /// <summary>The baked terrain's rectangle: (x, y, w, h).</summary>
        public static (double x, double y, double w, double h) BakeRect() =>
            (-HALF_W - BAKE_MARGIN, -HALF_L - BAKE_MARGIN, 2.0 * (HALF_W + BAKE_MARGIN), 2.0 * (HALF_L + BAKE_MARGIN));

        // ---------------- walls (for the sim) ----------------
        public static List<Wall> Walls()
        {
            var o = new List<Wall>();
            foreach (var rg in Ridges())
            {
                var pts = rg.pts;
                for (int i = 0; i < pts.Count - 1; i++) Edge(o, pts[i], pts[i + 1], rg.r, "rock");
            }
            var lp = EdgeLoop();
            int half = EDGE_BLUE.Length;
            for (int i = 0; i < lp.Count; i++)
            {
                int k = i % half;
                if (k == half - 1 || Array.IndexOf(EDGE_SKIP, k) >= 0) continue;
                Edge(o, lp[i], lp[(i + 1) % lp.Count], EDGE_R, "edge");
            }
            foreach (var w in o)
            {
                w.a = FixEnd(w.a);
                w.b = FixEnd(w.b);
            }
            return o;
        }

        static Vec2 FixEnd(Vec2 q)
        {
            if (Math.Abs(q.x) > HALF_W - 1.5 && Math.Abs(q.x) < HALF_W + 0.5) q.x = (float)(GD.Sign(q.x) * (HALF_W + 1.0));
            if (Math.Abs(q.y) > HALF_L - 1.5 && Math.Abs(q.y) < HALF_L + 0.5) q.y = (float)(GD.Sign(q.y) * (HALF_L + 1.0));
            return q;
        }

        static void Edge(List<Wall> o, Vec2 a, Vec2 b, double r, string kind)
        {
            Vec2 lim = new Vec2(HALF_W + 1.0, HALF_L + 1.0);
            double t0 = 0.0, t1 = 1.0;
            Vec2 d = b - a;
            for (int axis = 0; axis < 2; axis++)
            {
                double p0 = axis == 0 ? a.x : a.y;
                double dd = axis == 0 ? d.x : d.y;
                double la = axis == 0 ? lim.x : lim.y;
                foreach (double s in new[] { -1.0, 1.0 })
                {
                    double num = la - s * p0;
                    double den = s * dd;
                    if (Math.Abs(den) < 0.000001)
                    {
                        if (num < 0.0) return;
                    }
                    else if (den > 0.0) t1 = GD.Min(t1, num / den);
                    else t0 = GD.Max(t0, num / den);
                }
            }
            if (t1 - t0 <= 0.0) return;
            Vec2 ca = a + d * t0;
            Vec2 cb = a + d * t1;
            if (ca.DistanceTo(cb) < 0.2) return;
            o.Add(new Wall { a = ca, b = cb, r = r, team = -1, kind = kind });
        }
    }
}
