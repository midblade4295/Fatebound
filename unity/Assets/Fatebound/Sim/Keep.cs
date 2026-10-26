// The keep (keep.gd, 0.31.165+): each side's base at its end of the Rift. A round curtain wall with a gate facing each
// lane; inside it the King on his throne at the back and the fountain behind him. World coordinates for blue (team 0,
// the +y end); red's keep is the point mirror (x, y) -> (-x, -y). The sim builds its walls, gates and nav from this,
// the view the stonework.
using System;
using System.Collections.Generic;

namespace Fatebound.Sim
{
    public static class Keep
    {
        public static readonly Vec2 C = new Vec2(0.0f, 96.0f);      // the ring's middle
        public const double R = 14.0;                                // the wall's line
        public const double BACK = 110.0;
        public static readonly double[] GATE_ANG = { -0.75 * Math.PI, -0.5 * Math.PI, -0.25 * Math.PI };
        public static readonly string[] GATE_SIDE = { "west", "middle", "east" };
        public const double GATE_HALF = 1.75;
        public const double GATE_PIECE = 3.2;
        public const double GATEHOUSE_K = 1.2;
        public const double SEG = 5.6;
        public static readonly Vec2 KING = new Vec2(0.0f, 99.0f);
        public static readonly Vec2 THRONE_SEAT = new Vec2(0.0f, 100.6f);
        public const double THRONE_R = 0.9;
        public static readonly Vec2 FOUNTAIN = new Vec2(0.0f, 104.5f);
        public const double FOUNTAIN_R = 3.2;
        public static readonly Vec2[] KING_TOWERS = { new Vec2(-5.0f, 90.5f), new Vec2(5.0f, 90.5f) };
        public const double ZONE = R + 3.0;

        /// <summary>[model, spot (blue), turn (deg), height] -- the castle kit's props against the back of the wall.</summary>
        public static readonly (string model, Vec2 p, double turn, double h)[] PROPS =
        {
            ("royal_banner", new Vec2(-3.4f, 101.6f), 0.0, 3.4), ("royal_banner", new Vec2(3.4f, 101.6f), 0.0, 3.4),
            ("royal_statue", new Vec2(-7.6f, 104.2f), 25.0, 2.6), ("royal_statue", new Vec2(7.6f, 104.2f), -25.0, 2.6),
            ("royal_topiary", new Vec2(-10.6f, 99.5f), 0.0, 2.2), ("royal_topiary", new Vec2(10.6f, 99.5f), 0.0, 2.2),
        };
        public const string FOUNTAIN_MODEL = "royal_fountain";

        public static Vec2 RingPoint(double a, double r = R) => C + new Vec2(Math.Cos(a), Math.Sin(a)) * r;

        public static Vec2 GateC(int i) => RingPoint(GATE_ANG[i]);

        public static Vec2[] GateEnds(int i)
        {
            double a = GATE_ANG[i];
            double da = 2.0 * Math.Asin(GATE_HALF / (2.0 * R));
            return new[] { RingPoint(a - da), RingPoint(a + da) };
        }

        public static Vec2[] GatehouseEnds(int i)
        {
            double a = GATE_ANG[i];
            double da = 2.0 * Math.Asin(GATE_PIECE / (2.0 * R));
            return new[] { RingPoint(a - da), RingPoint(a + da) };
        }

        public static bool Inside(Vec2 q) => q.DistanceSquaredTo(C) < R * R;

        static List<Vec2[]> _ring;
        /// <summary>The wall's chords [a, b] (blue space) between the gatehouses, round the back from east to west.</summary>
        public static List<Vec2[]> Ring()
        {
            if (_ring != null) return _ring;
            var ring = new List<Vec2[]>();
            double da = 2.0 * Math.Asin(GATE_PIECE / (2.0 * R));
            var arcs = new List<double[]>();
            for (int i = 0; i < GATE_ANG.Length - 1; i++) arcs.Add(new[] { GATE_ANG[i] + da, GATE_ANG[i + 1] - da });
            arcs.Add(new[] { GATE_ANG[GATE_ANG.Length - 1] + da, GATE_ANG[0] + GD.TAU - da });
            foreach (var arc in arcs)
            {
                double a0 = arc[0], a1 = arc[1];
                int n = Math.Max(1, (int)GD.Round((a1 - a0) * R / SEG));
                for (int k = 0; k < n; k++)
                    ring.Add(new[] { RingPoint(GD.Lerp(a0, a1, (double)k / n)), RingPoint(GD.Lerp(a0, a1, (double)(k + 1) / n)) });
            }
            _ring = ring;
            return _ring;
        }

        /// <summary>Where two of the ring's chords meet (not at a gatehouse): the view stands a tower on every other one.</summary>
        public static List<Vec2> Joints()
        {
            var output = new List<Vec2>();
            var rg = Ring();
            for (int k = 0; k < rg.Count - 1; k++)
                if (rg[k][1].DistanceTo(rg[k + 1][0]) < 0.01) output.Add(rg[k][1]);
            return output;
        }
    }
}
