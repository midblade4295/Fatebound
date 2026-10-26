// Godot's AStarGrid2D (core/math/a_star_grid_2d.cpp, 4.7), the parts the sim uses: square cells, no jumping, a
// diagonal mode and the octile heuristic, weight scales, get_id_path with partial paths. Same open-list heap (Godot's
// SortArray push/pop), same neighbour order and float (real_t) arithmetic -- the same paths.
using System;
using System.Collections.Generic;

namespace Fatebound.Sim
{
    public sealed class AStarGrid
    {
        public enum Diagonal { Always, Never, AtLeastOneWalkable, OnlyIfNoObstacles }
        public enum Heuristic { Euclidean, Manhattan, Octile, Chebyshev }

        sealed class Point
        {
            public int x, y;
            public float weight = 1f;
            public Point prev;
            public float g, f, absG, absF;
            public ulong openPass, closedPass;
        }

        public int rx, ry, rw, rh;               // the region: position and size
        public Diagonal diagonal = Diagonal.Always;
        public Heuristic computeH = Heuristic.Euclidean;
        public Heuristic estimateH = Heuristic.Euclidean;

        bool[] solid;                            // with a solid border, as Godot's mask
        Point[] points;                          // [y * rw + x] (region-relative)
        ulong pass = 1;
        Point endP, lastClosest;
        readonly List<Point> open = new List<Point>();
        readonly List<Point> nbors = new List<Point>(8);
        Point[] heap = new Point[64];

        public AStarGrid(int x, int y, int w, int h)
        {
            rx = x; ry = y; rw = w; rh = h;
            Update();
        }

        public void Update()
        {
            solid = new bool[(rw + 2) * (rh + 2)];
            for (int i = 0; i < solid.Length; i++) solid[i] = true;
            points = new Point[rw * rh];
            for (int yy = 0; yy < rh; yy++)
                for (int xx = 0; xx < rw; xx++)
                {
                    points[yy * rw + xx] = new Point { x = rx + xx, y = ry + yy };
                    solid[MaskIndex(rx + xx, ry + yy)] = false;
                }
        }

        int MaskIndex(int x, int y) => ((y - ry + 1) * (rw + 2)) + x - rx + 1;
        Point P(int x, int y) => points[(y - ry) * rw + (x - rx)];

        public bool InBounds(int x, int y) => x >= rx && y >= ry && x < rx + rw && y < ry + rh;
        public bool InBounds(Vec2i c) => InBounds(c.x, c.y);

        public void SetSolid(Vec2i c, bool s = true)
        {
            if (!InBounds(c)) return;
            solid[MaskIndex(c.x, c.y)] = s;
        }

        public bool IsSolid(Vec2i c)
        {
            if (!InBounds(c)) return false;
            return solid[MaskIndex(c.x, c.y)];
        }

        public void SetWeight(Vec2i c, double w)
        {
            if (!InBounds(c) || w < 0.0) return;
            P(c.x, c.y).weight = (float)w;
        }

        public float GetWeight(Vec2i c) => InBounds(c) ? P(c.x, c.y).weight : 0f;

        static float H(Heuristic h, int fx, int fy, int tx, int ty)
        {
            float dx = Math.Abs(tx - fx);
            float dy = Math.Abs(ty - fy);
            switch (h)
            {
                case Heuristic.Manhattan: return dx + dy;
                case Heuristic.Octile:
                {
                    float F = (float)(1.4142135623730950488016887242 - 1.0);
                    return dx < dy ? F * dx + dy : F * dy + dx;
                }
                case Heuristic.Chebyshev: return dx > dy ? dx : dy;
                default: return MathF.Sqrt(dx * dx + dy * dy);
            }
        }

        bool Solid(Point p) => solid[MaskIndex(p.x, p.y)];

        void GetNbors(Point p)
        {
            nbors.Clear();
            bool ts0 = false, ts1 = false, ts2 = false, ts3 = false, td0 = false, td1 = false, td2 = false, td3 = false;
            Point left = null, right = null, top = null, bottom = null, tl = null, tr = null, bl = null, br = null;
            bool hasL = false, hasR = false;
            if (p.x - 1 >= rx) { left = P(p.x - 1, p.y); hasL = true; }
            if (p.x + 1 < rx + rw) { right = P(p.x + 1, p.y); hasR = true; }
            if (p.y - 1 >= ry)
            {
                top = P(p.x, p.y - 1);
                if (hasL) tl = P(p.x - 1, p.y - 1);
                if (hasR) tr = P(p.x + 1, p.y - 1);
            }
            if (p.y + 1 < ry + rh)
            {
                bottom = P(p.x, p.y + 1);
                if (hasL) bl = P(p.x - 1, p.y + 1);
                if (hasR) br = P(p.x + 1, p.y + 1);
            }
            if (top != null && !Solid(top)) { nbors.Add(top); ts0 = true; }
            if (right != null && !Solid(right)) { nbors.Add(right); ts1 = true; }
            if (bottom != null && !Solid(bottom)) { nbors.Add(bottom); ts2 = true; }
            if (left != null && !Solid(left)) { nbors.Add(left); ts3 = true; }
            switch (diagonal)
            {
                case Diagonal.Always: td0 = td1 = td2 = td3 = true; break;
                case Diagonal.AtLeastOneWalkable: td0 = ts3 || ts0; td1 = ts0 || ts1; td2 = ts1 || ts2; td3 = ts2 || ts3; break;
                case Diagonal.OnlyIfNoObstacles: td0 = ts3 && ts0; td1 = ts0 && ts1; td2 = ts1 && ts2; td3 = ts2 && ts3; break;
            }
            if (td0 && tl != null && !Solid(tl)) nbors.Add(tl);
            if (td1 && tr != null && !Solid(tr)) nbors.Add(tr);
            if (td2 && br != null && !Solid(br)) nbors.Add(br);
            if (td3 && bl != null && !Solid(bl)) nbors.Add(bl);
        }

        // SortPoints: true when a is worse than b
        static bool Worse(Point a, Point b)
        {
            if (a.f > b.f) return true;
            if (a.f < b.f) return false;
            return a.g < b.g;
        }

        static readonly Func<Point, Point, bool> WorseF = Worse;

        bool Solve(Point begin, Point end, bool partial)
        {
            lastClosest = null;
            pass++;
            if (Solid(begin)) return false;
            if (begin == end) return true;
            if (Solid(end) && !partial) return false;
            bool found = false;
            int n = 0;                           // the open list lives in `heap` (Godot's LocalVector + SortArray)
            begin.g = 0;
            begin.f = H(estimateH, begin.x, begin.y, end.x, end.y);
            begin.absG = 0;
            begin.absF = H(estimateH, begin.x, begin.y, end.x, end.y);
            heap[n++] = begin;
            endP = end;
            while (n > 0)
            {
                Point p = heap[0];
                if (lastClosest == null || lastClosest.absF > p.absF || (lastClosest.absF >= p.absF && lastClosest.absG > p.absG))
                    lastClosest = p;
                if (p == end)
                {
                    found = true;
                    break;
                }
                GSort.PopHeap(heap, 0, n, WorseF);
                n--;
                p.closedPass = pass;
                GetNbors(p);
                for (int i = 0; i < nbors.Count; i++)
                {
                    Point e = nbors[i];
                    if (Solid(e) || e.closedPass == pass) continue;
                    float ws = e.weight;
                    float tg = p.g + H(computeH, p.x, p.y, e.x, e.y) * ws;
                    bool isNew = false;
                    if (e.openPass != pass)
                    {
                        e.openPass = pass;
                        if (n == heap.Length) Array.Resize(ref heap, n * 2);
                        heap[n++] = e;
                        isNew = true;
                    }
                    else if (tg >= e.g) continue;
                    e.prev = p;
                    e.g = tg;
                    e.f = e.g + H(estimateH, e.x, e.y, end.x, end.y);
                    e.absG = tg;
                    e.absF = e.f - e.g;
                    if (isNew) GSort.PushHeap(heap, 0, n - 1, 0, e, WorseF);
                    else GSort.PushHeap(heap, 0, Array.IndexOf(heap, e, 0, n), 0, e, WorseF);
                }
            }
            return found;
        }

        /// <summary>get_id_path(from, to, allow_partial_path): the cells from `from` to `to` (both included).</summary>
        public List<Vec2i> GetIdPath(Vec2i from, Vec2i to, bool partial)
        {
            var path = new List<Vec2i>();
            if (!InBounds(from) || !InBounds(to)) return path;
            Point begin = P(from.x, from.y);
            Point end = P(to.x, to.y);
            bool found = Solve(begin, end, partial);
            if (!found)
            {
                if (!partial || lastClosest == null) return path;
                end = lastClosest;
            }
            Point p = end;
            int pc = 1;
            while (p != begin) { pc++; p = p.prev; }
            var arr = new Vec2i[pc];
            p = end;
            int idx = pc - 1;
            while (p != begin) { arr[idx--] = new Vec2i(p.x, p.y); p = p.prev; }
            arr[0] = new Vec2i(p.x, p.y);
            path.AddRange(arr);
            return path;
        }
    }
}
