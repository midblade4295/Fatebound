// Godot's Dictionary and Array for the ported game code (see Var.cs). Both are reference types shared by assignment,
// as in Godot; duplicate() copies. GDict keeps insertion order (erase then set appends at the end), keys compare
// type-strictly (Var.Equals). GArray's find/has/erase compare type-strictly too ([1].has(1.0) is false), its
// sort() and sort_custom() are Godot's SortArray (GSort) so ties land where Godot puts them.
using System;
using System.Collections;
using System.Collections.Generic;

namespace Fatebound.Sim
{
    public sealed class GDict : IEnumerable<Var>
    {
        Var[] _k = Array.Empty<Var>();
        Var[] _v = Array.Empty<Var>();
        bool[] _dead = Array.Empty<bool>();
        int _used, _live;
        readonly Dictionary<Var, int> _idx = new Dictionary<Var, int>();
        bool _readOnly;

        public GDict() { }

        public GDict(int capacity)
        {
            _k = new Var[capacity];
            _v = new Var[capacity];
            _dead = new bool[capacity];
        }

        /// <summary>GDict.Of("ok", false, "error", "x") == {"ok": false, "error": "x"}.</summary>
        public static GDict Of(params Var[] kv)
        {
            var d = new GDict(kv.Length / 2);
            for (int i = 0; i + 1 < kv.Length; i += 2) d[kv[i]] = kv[i + 1];
            return d;
        }

        /// <summary>(collection initializer: new GDict { {"a", 1}, {"b", 2} })</summary>
        public void Add(Var key, Var value) => this[key] = value;

        public int Size() => _live;
        public int Count => _live;
        public bool IsEmpty() => _live == 0;

        public Var this[Var key]
        {
            get
            {
                if (_idx.TryGetValue(key, out int i)) return _v[i];
                GD.PushError("Invalid access to key " + GFormat.Clean(key) + " on a Dictionary.");
                return Var.Nil;
            }
            set
            {
                if (_readOnly) { GD.PushError("Dictionary is in read-only state."); return; }
                if (_idx.TryGetValue(key, out int i)) { _v[i] = value; return; }
                if (_used == _k.Length) Grow();
                _k[_used] = key;
                _v[_used] = value;
                _dead[_used] = false;
                _idx[key] = _used;
                _used++;
                _live++;
            }
        }

        void Grow()
        {
            if (_used - _live > _live / 2 && _used - _live > 4) { Compact(); if (_used < _k.Length) return; }
            int n = Math.Max(4, _k.Length * 2);
            Array.Resize(ref _k, n);
            Array.Resize(ref _v, n);
            Array.Resize(ref _dead, n);
        }

        void Compact()
        {
            int w = 0;
            for (int r = 0; r < _used; r++)
            {
                if (_dead[r]) continue;
                if (w != r)
                {
                    _k[w] = _k[r];
                    _v[w] = _v[r];
                    _dead[w] = false;
                    _idx[_k[w]] = w;
                }
                w++;
            }
            for (int i = w; i < _used; i++) { _k[i] = default; _v[i] = default; _dead[i] = false; }
            _used = w;
        }

        public Var Get(Var key, Var dflt = default) => _idx.TryGetValue(key, out int i) ? _v[i] : dflt;
        public bool TryGetValue(Var key, out Var value)
        {
            if (_idx.TryGetValue(key, out int i)) { value = _v[i]; return true; }
            value = Var.Nil;
            return false;
        }

        /// <summary>get_or_add(key, default): the value, adding the default first when the key is missing.</summary>
        public Var GetOrAdd(Var key, Var dflt = default)
        {
            if (_idx.TryGetValue(key, out int i)) return _v[i];
            this[key] = dflt;
            return dflt;
        }

        public bool Has(Var key) => _idx.ContainsKey(key);
        public bool ContainsKey(Var key) => _idx.ContainsKey(key);

        public bool HasAll(GArray keys)
        {
            for (int i = 0; i < keys.Size(); i++) if (!Has(keys[i])) return false;
            return true;
        }

        public bool Erase(Var key)
        {
            if (_readOnly) { GD.PushError("Dictionary is in read-only state."); return false; }
            if (!_idx.TryGetValue(key, out int i)) return false;
            _idx.Remove(key);
            _dead[i] = true;
            _k[i] = default;
            _v[i] = default;
            _live--;
            if (_live == 0) { _used = 0; }
            else if (i == _used - 1) { while (_used > 0 && _dead[_used - 1]) { _dead[_used - 1] = false; _used--; } }
            return true;
        }

        public void Clear()
        {
            if (_readOnly) { GD.PushError("Dictionary is in read-only state."); return; }
            Array.Clear(_k, 0, _used);
            Array.Clear(_v, 0, _used);
            Array.Clear(_dead, 0, _used);
            _idx.Clear();
            _used = _live = 0;
        }

        public GArray Keys()
        {
            var a = new GArray(_live);
            for (int i = 0; i < _used; i++) if (!_dead[i]) a.Append(_k[i]);
            return a;
        }

        public GArray Values()
        {
            var a = new GArray(_live);
            for (int i = 0; i < _used; i++) if (!_dead[i]) a.Append(_v[i]);
            return a;
        }

        /// <summary>The live keys in order, without an array (safe while values change; not while keys are added).</summary>
        public IEnumerable<KeyValuePair<Var, Var>> Pairs()
        {
            for (int i = 0; i < _used; i++)
                if (!_dead[i]) yield return new KeyValuePair<Var, Var>(_k[i], _v[i]);
        }

        public GDict Duplicate(bool deep = false)
        {
            var d = new GDict(_live);
            for (int i = 0; i < _used; i++)
            {
                if (_dead[i]) continue;
                d[deep ? _k[i].Duplicate(true) : _k[i]] = deep ? _v[i].Duplicate(true) : _v[i];
            }
            return d;
        }

        /// <summary>merge(other, overwrite): adds the other's entries (keeping existing ones unless overwrite).</summary>
        public void Merge(GDict other, bool overwrite = false)
        {
            foreach (var kv in other.Pairs())
                if (overwrite || !Has(kv.Key)) this[kv.Key] = kv.Value;
        }

        public GDict Merged(GDict other, bool overwrite = false)
        {
            var d = Duplicate();
            d.Merge(other, overwrite);
            return d;
        }

        /// <summary>find_key(value): the first key whose value equals it (type-strict), or Nil.</summary>
        public Var FindKey(Var value)
        {
            for (int i = 0; i < _used; i++)
                if (!_dead[i] && Var.HashCompare(_v[i], value, 0)) return _k[i];
            return Var.Nil;
        }

        public void MakeReadOnly() => _readOnly = true;
        public bool IsReadOnly() => _readOnly;

        public uint Hash() => RecursiveHash(0);

        internal uint RecursiveHash(int depth)
        {
            if (depth > 100) { GD.PushError("Max recursion reached"); return 0; }
            uint h = GHashing.Murmur3One32((uint)GD.TYPE_DICTIONARY);
            for (int i = 0; i < _used; i++)
            {
                if (_dead[i]) continue;
                h = GHashing.Murmur3One32(_k[i].GodotHash(depth + 1), h);
                h = GHashing.Murmur3One32(_v[i].GodotHash(depth + 1), h);
            }
            return GHashing.Fmix32(h);
        }

        internal static bool RecursiveHashCompare(GDict a, GDict b, int depth)
        {
            if (ReferenceEquals(a, b)) return true;
            if (a._live != b._live) return false;
            if (depth > 100) return true;
            for (int i = 0; i < a._used; i++)
            {
                if (a._dead[i]) continue;
                if (!b._idx.TryGetValue(a._k[i], out int j)) return false;
                if (!Var.HashCompare(a._v[i], b._v[j], depth + 1)) return false;
            }
            return true;
        }

        internal static bool RecursiveEqual(GDict a, GDict b, int depth) => RecursiveHashCompare(a, b, depth);

        // `for k in d` walks the keys in order
        public Enumerator GetEnumerator() => new Enumerator(this);
        IEnumerator<Var> IEnumerable<Var>.GetEnumerator() => GetEnumerator();
        IEnumerator IEnumerable.GetEnumerator() => GetEnumerator();

        public struct Enumerator : IEnumerator<Var>
        {
            readonly GDict _d;
            int _i;
            public Enumerator(GDict d) { _d = d; _i = -1; }
            public Var Current => _d._k[_i];
            object IEnumerator.Current => Current;
            public bool MoveNext()
            {
                while (++_i < _d._used) if (!_d._dead[_i]) return true;
                return false;
            }
            public void Reset() => _i = -1;
            public void Dispose() { }
        }

        public override string ToString() => GFormat.Str(this);
    }

    public sealed class GArray : IEnumerable<Var>
    {
        readonly List<Var> _a;
        bool _readOnly;

        public GArray() { _a = new List<Var>(); }
        public GArray(int capacity) { _a = new List<Var>(capacity); }
        public GArray(IEnumerable<Var> items) { _a = new List<Var>(items); }

        /// <summary>GArray.Of(1, "a", v) == [1, "a", v].</summary>
        public static GArray Of(params Var[] items) => new GArray(items);

        /// <summary>Any list or array as a GArray (Array(packed_array)).</summary>
        public static GArray From(IEnumerable items)
        {
            var a = new GArray();
            if (items != null) foreach (var x in items) a.Append(Var.Of(x));
            return a;
        }

        public void Add(Var v) => Append(v);           // (collection initializer: new GArray { 1, "a" })

        /// <summary>The underlying list (fast typed loops; changes show in the array).</summary>
        public List<Var> List => _a;

        public int Size() => _a.Count;
        public bool IsEmpty() => _a.Count == 0;

        public Var this[int i]
        {
            get
            {
                if (i < 0) i += _a.Count;
                if ((uint)i >= (uint)_a.Count) { GD.PushError("Out of bounds get index '" + i + "' (on base: 'Array')"); return Var.Nil; }
                return _a[i];
            }
            set
            {
                if (_readOnly) { GD.PushError("Array is in read-only state."); return; }
                if (i < 0) i += _a.Count;
                if ((uint)i >= (uint)_a.Count) { GD.PushError("Out of bounds set index '" + i + "' (on base: 'Array')"); return; }
                _a[i] = value;
            }
        }

        public Var Get(int i, Var dflt = default)
        {
            if (i < 0) i += _a.Count;
            return (uint)i < (uint)_a.Count ? _a[i] : dflt;
        }

        bool Ro()
        {
            if (_readOnly) GD.PushError("Array is in read-only state.");
            return _readOnly;
        }

        public void Append(Var v) { if (!Ro()) _a.Add(v); }
        public void PushBack(Var v) => Append(v);
        public void PushFront(Var v) { if (!Ro()) _a.Insert(0, v); }
        public void AppendArray(GArray other) { if (!Ro()) _a.AddRange(other._a); }

        public void Insert(int pos, Var v)
        {
            if (Ro()) return;
            if (pos < 0) pos += _a.Count;
            if (pos < 0 || pos > _a.Count) { GD.PushError("Array.insert: index out of range."); return; }
            _a.Insert(pos, v);
        }

        public void RemoveAt(int i)
        {
            if (Ro()) return;
            if (i < 0) i += _a.Count;
            if ((uint)i >= (uint)_a.Count) { GD.PushError("Array.remove_at: index out of range."); return; }
            _a.RemoveAt(i);
        }

        /// <summary>erase(value): removes the first element equal to it (type-strict).</summary>
        public void Erase(Var v)
        {
            if (Ro()) return;
            int i = Find(v);
            if (i >= 0) _a.RemoveAt(i);
        }

        public int Find(Var v, int from = 0)
        {
            int n = _a.Count;
            if (from < 0) { from += n; if (from < 0) from = 0; }
            for (int i = from; i < n; i++) if (Var.HashCompare(_a[i], v, 0)) return i;
            return -1;
        }

        public int FindCustom(Func<Var, bool> pred, int from = 0)
        {
            int n = _a.Count;
            if (from < 0) { from += n; if (from < 0) from = 0; }
            for (int i = from; i < n; i++) if (pred(_a[i])) return i;
            return -1;
        }

        public int RFind(Var v, int from = -1)
        {
            int n = _a.Count;
            if (from < 0) from += n;
            if (from >= n) from = n - 1;
            for (int i = from; i >= 0; i--) if (Var.HashCompare(_a[i], v, 0)) return i;
            return -1;
        }

        public bool Has(Var v) => Find(v) >= 0;
        public bool Contains(Var v) => Find(v) >= 0;

        public int Count(Var v)
        {
            int c = 0;
            for (int i = 0; i < _a.Count; i++) if (Var.HashCompare(_a[i], v, 0)) c++;
            return c;
        }

        public void Clear() { if (!Ro()) _a.Clear(); }

        public void Resize(int n)
        {
            if (Ro()) return;
            if (n < _a.Count) _a.RemoveRange(n, _a.Count - n);
            else while (_a.Count < n) _a.Add(Var.Nil);
        }

        public void Fill(Var v)
        {
            if (Ro()) return;
            for (int i = 0; i < _a.Count; i++) _a[i] = v;
        }

        public GArray Duplicate(bool deep = false)
        {
            var r = new GArray(_a.Count);
            if (!deep) r._a.AddRange(_a);
            else foreach (var x in _a) r._a.Add(x.Duplicate(true));
            return r;
        }

        /// <summary>slice(begin, end, step, deep) with Godot's clamping of negative and out-of-range bounds.</summary>
        public GArray Slice(int begin, int end = int.MaxValue, int step = 1, bool deep = false)
        {
            var result = new GArray();
            if (step == 0) { GD.PushError("Slice step cannot be zero."); return result; }
            int s = _a.Count;
            if (s == 0 || (begin < -s && step < 0) || (begin >= s && step > 0)) return result;
            int b = Math.Max(-s, Math.Min(begin, s - 1));
            if (b < 0) b += s;
            long e0 = Math.Max(-s - 1L, Math.Min((long)end, s));
            int e = (int)e0;
            if (e < 0) e += s;
            if (step > 0 && b > e) { GD.PushError("Slice step is positive, but bounds are decreasing."); return result; }
            if (step < 0 && b < e) { GD.PushError("Slice step is negative, but bounds are increasing."); return result; }
            int n = (e - b) / step + (((e - b) % step != 0) ? 1 : 0);
            for (int src = b, k = 0; k < n; ++k, src += step) result._a.Add(deep ? _a[src].Duplicate(true) : _a[src]);
            return result;
        }

        public void Reverse() { if (!Ro()) _a.Reverse(); }

        /// <summary>sort(): ascending by GDScript's `<` (Godot's SortArray, ties as Godot leaves them).</summary>
        public void Sort()
        {
            if (Ro()) return;
            GSort.Sort(_a, (x, y) => Var.Less(x, y));
        }

        /// <summary>sort_custom(func(a, b): return a goes before b).</summary>
        public void SortCustom(Func<Var, Var, bool> less)
        {
            if (Ro()) return;
            GSort.Sort(_a, less);
        }

        /// <summary>shuffle(): Godot's Fisher-Yates on the global random generator.</summary>
        public void Shuffle()
        {
            if (Ro()) return;
            int n = _a.Count;
            if (n < 2) return;
            for (int i = n - 1; i >= 1; i--)
            {
                int j = (int)(GD.GlobalRng.Next() % (uint)(i + 1));
                var t = _a[i]; _a[i] = _a[j]; _a[j] = t;
            }
        }

        public Var PickRandom()
        {
            if (_a.Count == 0) { GD.PushError("Can't take value from empty array."); return Var.Nil; }
            return _a[(int)(GD.GlobalRng.Next() % (uint)_a.Count)];
        }

        public Var PopFront()
        {
            if (_a.Count == 0 || Ro()) return Var.Nil;
            var v = _a[0];
            _a.RemoveAt(0);
            return v;
        }

        public Var PopBack()
        {
            if (_a.Count == 0 || Ro()) return Var.Nil;
            var v = _a[_a.Count - 1];
            _a.RemoveAt(_a.Count - 1);
            return v;
        }

        public Var PopAt(int i)
        {
            if (Ro()) return Var.Nil;
            if (i < 0) i += _a.Count;
            if ((uint)i >= (uint)_a.Count) { GD.PushError("Array.pop_at: index out of range."); return Var.Nil; }
            var v = _a[i];
            _a.RemoveAt(i);
            return v;
        }

        public Var Front()
        {
            if (_a.Count == 0) { GD.PushError("Can't take value from empty array."); return Var.Nil; }
            return _a[0];
        }

        public Var Back()
        {
            if (_a.Count == 0) { GD.PushError("Can't take value from empty array."); return Var.Nil; }
            return _a[_a.Count - 1];
        }

        public Var Max()
        {
            if (_a.Count == 0) return Var.Nil;
            var m = _a[0];
            for (int i = 1; i < _a.Count; i++)
            {
                if (!Comparable(m, _a[i])) return Var.Nil;
                if (Var.Less(m, _a[i])) m = _a[i];
            }
            return m;
        }

        public Var Min()
        {
            if (_a.Count == 0) return Var.Nil;
            var m = _a[0];
            for (int i = 1; i < _a.Count; i++)
            {
                if (!Comparable(m, _a[i])) return Var.Nil;
                if (Var.Less(_a[i], m)) m = _a[i];
            }
            return m;
        }

        static bool Comparable(Var a, Var b) => (a.IsNum && b.IsNum) || a.Type == b.Type;

        public GArray Filter(Func<Var, bool> pred)
        {
            var r = new GArray();
            foreach (var x in _a) if (pred(x)) r._a.Add(x);
            return r;
        }

        public GArray Map(Func<Var, Var> f)
        {
            var r = new GArray(_a.Count);
            foreach (var x in _a) r._a.Add(f(x));
            return r;
        }

        /// <summary>reduce(func(accum, x), accum): with no accum the first element starts it.</summary>
        public Var Reduce(Func<Var, Var, Var> f, Var accum = default, bool hasAccum = true)
        {
            int start = 0;
            if (!hasAccum)
            {
                if (_a.Count == 0) return Var.Nil;
                accum = _a[0];
                start = 1;
            }
            for (int i = start; i < _a.Count; i++) accum = f(accum, _a[i]);
            return accum;
        }

        public bool Any(Func<Var, bool> pred)
        {
            foreach (var x in _a) if (pred(x)) return true;
            return false;
        }

        public bool All(Func<Var, bool> pred)
        {
            foreach (var x in _a) if (!pred(x)) return false;
            return true;
        }

        /// <summary>bsearch(value, before): the insertion index in a sorted array.</summary>
        public int BSearch(Var v, bool before = true) => BSearchCustom(v, (a, b) => Var.Less(a, b), before);

        public int BSearchCustom(Var v, Func<Var, Var, bool> less, bool before = true)
        {
            int lo = 0, hi = _a.Count;
            if (before)
            {
                while (lo < hi)
                {
                    int mid = (lo + hi) / 2;
                    if (less(_a[mid], v)) lo = mid + 1; else hi = mid;
                }
            }
            else
            {
                while (lo < hi)
                {
                    int mid = (lo + hi) / 2;
                    if (less(v, _a[mid])) hi = mid; else lo = mid + 1;
                }
            }
            return lo;
        }

        public void MakeReadOnly() => _readOnly = true;
        public bool IsReadOnly() => _readOnly;

        public uint Hash() => RecursiveHash(0);

        internal uint RecursiveHash(int depth)
        {
            if (depth > 100) { GD.PushError("Max recursion reached"); return 0; }
            uint h = GHashing.Murmur3One32((uint)GD.TYPE_ARRAY);
            foreach (var x in _a) h = GHashing.Murmur3One32(x.GodotHash(depth + 1), h);
            return GHashing.Fmix32(h);
        }

        internal static bool RecursiveHashCompare(GArray a, GArray b, int depth)
        {
            if (ReferenceEquals(a, b)) return true;
            if (a._a.Count != b._a.Count) return false;
            if (depth > 100) return true;
            for (int i = 0; i < a._a.Count; i++)
                if (!Var.HashCompare(a._a[i], b._a[i], depth + 1)) return false;
            return true;
        }

        internal static bool RecursiveEqual(GArray a, GArray b, int depth) => RecursiveHashCompare(a, b, depth);

        internal static bool LessThan(GArray a, GArray b)
        {
            int n = Math.Min(a._a.Count, b._a.Count);
            for (int i = 0; i < n; i++)
            {
                if (Var.Less(a._a[i], b._a[i])) return true;
                if (Var.Less(b._a[i], a._a[i])) return false;
            }
            return a._a.Count < b._a.Count;
        }

        /// <summary>The elements as a typed list (PackedStringArray(arr), Array[int](arr)...).</summary>
        public List<string> ToStrings() { var r = new List<string>(_a.Count); foreach (var x in _a) r.Add(x.AsString()); return r; }
        public List<int> ToInts() { var r = new List<int>(_a.Count); foreach (var x in _a) r.Add(x.AsInt()); return r; }
        public List<double> ToFloats() { var r = new List<double>(_a.Count); foreach (var x in _a) r.Add(x.AsFloat()); return r; }
        public List<GDict> ToDicts() { var r = new List<GDict>(_a.Count); foreach (var x in _a) r.Add(x.AsDict()); return r; }

        // `for x in arr`: by index against the live size, as GDScript iterates (changing the array inside the loop
        // doesn't throw, as List's own enumerator would)
        public Enumerator GetEnumerator() => new Enumerator(_a);
        IEnumerator<Var> IEnumerable<Var>.GetEnumerator() => new Enumerator(_a);
        IEnumerator IEnumerable.GetEnumerator() => new Enumerator(_a);

        public struct Enumerator : IEnumerator<Var>
        {
            readonly List<Var> _l;
            int _i;
            public Enumerator(List<Var> l) { _l = l; _i = -1; }
            public Var Current => _l[_i];
            object IEnumerator.Current => Current;
            public bool MoveNext() => ++_i < _l.Count;
            public void Reset() => _i = -1;
            public void Dispose() { }
        }

        public override string ToString() => GFormat.Str(this);
    }
}
