// Godot container behaviour the sim relies on for identical results: an insertion-ordered dictionary whose erase +
// re-insert moves the key to the end (Godot's Dictionary; .NET's Dictionary reuses freed slots), and Godot's
// SortArray (introsort + insertion sort; not stable -- Array.sort_custom on ties).
using System;
using System.Collections;
using System.Collections.Generic;

namespace Fatebound.Sim
{
    /// <summary>Godot's Dictionary order: iteration in insertion order; erase then set appends at the end.</summary>
    public sealed class ODict<K, V> : IEnumerable<KeyValuePair<K, V>>
    {
        readonly Dictionary<K, V> map = new Dictionary<K, V>();
        readonly List<K> order = new List<K>();

        public int Count => map.Count;
        public bool IsEmpty => map.Count == 0;
        public bool Has(K k) => map.ContainsKey(k);
        public bool ContainsKey(K k) => map.ContainsKey(k);
        public V Get(K k, V dflt) => map.TryGetValue(k, out var v) ? v : dflt;
        public bool TryGetValue(K k, out V v) => map.TryGetValue(k, out v);

        public V this[K k]
        {
            get => map[k];
            set
            {
                if (!map.ContainsKey(k)) order.Add(k);
                map[k] = value;
            }
        }

        public bool Erase(K k)
        {
            if (!map.Remove(k)) return false;
            order.Remove(k);
            return true;
        }

        public void Clear() { map.Clear(); order.Clear(); }

        /// <summary>A snapshot of the keys (safe to erase while walking it), as Godot's keys().</summary>
        public List<K> Keys() => new List<K>(order);
        public IReadOnlyList<K> KeysLive => order;

        public ODict<K, V> Duplicate()
        {
            var d = new ODict<K, V>();
            foreach (var k in order) d[k] = map[k];
            return d;
        }

        public IEnumerator<KeyValuePair<K, V>> GetEnumerator()
        {
            for (int i = 0; i < order.Count; i++) yield return new KeyValuePair<K, V>(order[i], map[order[i]]);
        }
        IEnumerator IEnumerable.GetEnumerator() => GetEnumerator();
    }

    /// <summary>Godot's SortArray (core/templates/sort_array.h): Array.sort_custom's exact order, ties included.</summary>
    public static class GSort
    {
        const int THRESHOLD = 16;

        /// <summary>less(a, b): a goes before b.</summary>
        public static void Sort<T>(List<T> list, Func<T, T, bool> less)
        {
            int n = list.Count;
            if (n < 2) return;
            var a = list.ToArray();
            SortRange(a, 0, n, less);
            for (int i = 0; i < n; i++) list[i] = a[i];
        }

        public static void Sort<T>(T[] a, Func<T, T, bool> less)
        {
            if (a.Length < 2) return;
            SortRange(a, 0, a.Length, less);
        }

        static void SortRange<T>(T[] a, int first, int last, Func<T, T, bool> c)
        {
            if (first != last)
            {
                Introsort(a, first, last, Bitlog(last - first) * 2, c);
                FinalInsertionSort(a, first, last, c);
            }
        }

        static int Bitlog(int n)
        {
            int k;
            for (k = 0; n != 1; n >>= 1) ++k;
            return k;
        }

        static int Median<T>(T[] p, int ai, int bi, int ci, Func<T, T, bool> c)
        {
            T a = p[ai], b = p[bi], cc = p[ci];
            if (c(a, b))
            {
                if (c(b, cc)) return bi;
                else if (c(a, cc)) return ci;
                else return ai;
            }
            else if (c(a, cc)) return ai;
            else if (c(b, cc)) return ci;
            else return bi;
        }

        public static void PushHeap<T>(T[] a, int first, int hole, int top, T value, Func<T, T, bool> c)
        {
            int parent = (hole - 1) / 2;
            while (hole > top && c(a[first + parent], value))
            {
                a[first + hole] = a[first + parent];
                hole = parent;
                parent = (hole - 1) / 2;
            }
            a[first + hole] = value;
        }

        public static void PopHeap<T>(T[] a, int first, int last, int result, T value, Func<T, T, bool> c)
        {
            a[result] = a[first];
            AdjustHeap(a, first, 0, last - first, value, c);
        }

        public static void PopHeap<T>(T[] a, int first, int last, Func<T, T, bool> c)
        {
            PopHeap(a, first, last - 1, last - 1, a[last - 1], c);
        }

        static void AdjustHeap<T>(T[] a, int first, int hole, int len, T value, Func<T, T, bool> c)
        {
            int top = hole;
            int second = 2 * hole + 2;
            while (second < len)
            {
                if (c(a[first + second], a[first + (second - 1)])) second--;
                a[first + hole] = a[first + second];
                hole = second;
                second = 2 * (second + 1);
            }
            if (second == len)
            {
                a[first + hole] = a[first + (second - 1)];
                hole = second - 1;
            }
            PushHeap(a, first, hole, top, value, c);
        }

        static void SortHeap<T>(T[] a, int first, int last, Func<T, T, bool> c)
        {
            while (last - first > 1) PopHeap(a, first, last--, c);
        }

        static void MakeHeap<T>(T[] a, int first, int last, Func<T, T, bool> c)
        {
            if (last - first < 2) return;
            int len = last - first;
            int parent = (len - 2) / 2;
            while (true)
            {
                AdjustHeap(a, first, parent, len, a[first + parent], c);
                if (parent == 0) return;
                parent--;
            }
        }

        static void PartialSort<T>(T[] a, int first, int last, int middle, Func<T, T, bool> c)
        {
            MakeHeap(a, first, middle, c);
            for (int i = middle; i < last; i++)
                if (c(a[i], a[first])) PopHeap(a, first, middle, i, a[i], c);
            SortHeap(a, first, middle, c);
        }

        static int Partitioner<T>(T[] a, int first, int last, int pivot, Func<T, T, bool> c)
        {
            int piv = pivot;                       // (the pivot element's slot, followed through the swaps)
            while (true)
            {
                while (first != pivot && c(a[first], a[piv])) first++;
                last--;
                while (last != pivot && c(a[piv], a[last])) last--;
                if (first >= last) return first;
                if (piv == first) piv = last;
                else if (piv == last) piv = first;
                T tmp = a[first]; a[first] = a[last]; a[last] = tmp;
                first++;
            }
        }

        static void Introsort<T>(T[] a, int first, int last, int depth, Func<T, T, bool> c)
        {
            while (last - first > THRESHOLD)
            {
                if (depth == 0)
                {
                    PartialSort(a, first, last, last, c);
                    return;
                }
                depth--;
                int cut = Partitioner(a, first, last, Median(a, first, first + (last - first) / 2, last - 1, c), c);
                Introsort(a, cut, last, depth, c);
                last = cut;
            }
        }

        static void UnguardedLinearInsert<T>(T[] a, int last, T value, Func<T, T, bool> c)
        {
            int next = last - 1;
            while (c(value, a[next]))
            {
                a[last] = a[next];
                last = next;
                next--;
            }
            a[last] = value;
        }

        static void LinearInsert<T>(T[] a, int first, int last, Func<T, T, bool> c)
        {
            T val = a[last];
            if (c(val, a[first]))
            {
                for (int i = last; i > first; i--) a[i] = a[i - 1];
                a[first] = val;
            }
            else UnguardedLinearInsert(a, last, val, c);
        }

        static void InsertionSort<T>(T[] a, int first, int last, Func<T, T, bool> c)
        {
            if (first == last) return;
            for (int i = first + 1; i != last; i++) LinearInsert(a, first, i, c);
        }

        static void UnguardedInsertionSort<T>(T[] a, int first, int last, Func<T, T, bool> c)
        {
            for (int i = first; i != last; i++) UnguardedLinearInsert(a, i, a[i], c);
        }

        static void FinalInsertionSort<T>(T[] a, int first, int last, Func<T, T, bool> c)
        {
            if (last - first > THRESHOLD)
            {
                InsertionSort(a, first, first + THRESHOLD, c);
                UnguardedInsertionSort(a, first + THRESHOLD, last, c);
            }
            else InsertionSort(a, first, last, c);
        }
    }
}
