// Godot's binary Variant format (core/io/marshalls.cpp encode_variant / decode_variant) byte for byte: var_to_bytes /
// bytes_to_var, so this client and a Godot server read each other's messages (the online protocol is var_to_bytes of a
// Dictionary over a WebSocket). Plus Marshalls' base64 helpers and Godot's text format (core/variant/variant_parser.cpp:
// var_to_str / str_to_var, and the [section] / key=value reader ConfigFile uses). Engine-free: a .NET server can use it.
//
// Types: Var's own (null, bool, int, float, String, Vector2/2i/3, Dictionary, Array) map directly; packed arrays are C#
// arrays (byte[] int[] long[] float[] double[] string[] Vec2[] Vec3[]; List<T> of those encode too). Godot value types this
// assembly has no struct for (Color and Rect2 live in the GUI assembly, Transform3D & co. in the 3D facade) go through a
// registry: GMarshal.Register<T>(godotType, toComponents, fromComponents) maps a C# struct to a Godot type by its
// components in Godot's binary order (the GUI assembly registers Col, Rect2 and Xform2 -- see GUI/Services/Platform.cs).
// A type nobody registered decodes to a GValue (type number + components) that re-encodes to the same bytes and prints
// as Godot prints it. Objects encode as Godot does without full objects (an instance id); decoding never builds objects.
// Real numbers are single precision (real_t = float), as the standard Godot build the game ships with.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace Fatebound.Sim
{
    /// <summary>A Godot value of a type the runtime has no C# struct registered for (Rect2i, Vector3i, Vector4, Plane,
    /// Quaternion, AABB, Basis, Transform2D/3D, Projection; Color and Rect2 before the GUI registers its own): its type
    /// number and its components in Godot's binary order (Basis by rows, Transform2D by columns, Projection by columns).</summary>
    public sealed class GValue : IGodotValue, IEquatable<GValue>
    {
        public readonly int Type;
        public readonly double[] C;

        public GValue(int type, params double[] components)
        {
            Type = type;
            C = components ?? new double[GMarshal.ComponentCount(type)];
        }

        public int GodotType => Type;
        public bool GodotIsZero
        {
            get
            {
                foreach (var c in C) if (c != 0) return false;
                return true;
            }
        }

        public uint GodotHash()
        {
            uint h = GHashing.MURMUR3_SEED;
            bool ints = GMarshal.IsIntType(Type);
            foreach (var c in C) h = ints ? GHashing.Murmur3One32(unchecked((uint)(int)c), h) : GHashing.Murmur3OneFloat((float)c, h);
            return GHashing.Fmix32(h);
        }

        public bool GodotOp(char op, Var other, bool selfLeft, out Var result) { result = Var.Nil; return false; }
        public string GodotStr() => GMarshal.StrOf(Type, C);
        public override string ToString() => GodotStr();

        public bool Equals(GValue o)
        {
            if (o is null || o.Type != Type || o.C.Length != C.Length) return false;
            for (int i = 0; i < C.Length; i++) if (!(C[i] == o.C[i] || (double.IsNaN(C[i]) && double.IsNaN(o.C[i])))) return false;
            return true;
        }

        public override bool Equals(object obj) => obj is GValue g && Equals(g);
        public override int GetHashCode() => unchecked((int)GodotHash());
    }

    /// <summary>What bytes_to_var gives for an object sent as its instance id (Godot's EncodedObjectAsID).</summary>
    public sealed class EncodedObjectAsID
    {
        public ulong ObjectId;
        public ulong GetObjectId() => ObjectId;
        public override string ToString() => "<EncodedObjectAsID#" + unchecked((long)ObjectId) + ">";
    }

    public static class GMarshal
    {
        const uint HEADER_TYPE_MASK = 0xFF;
        const uint FLAG_64 = 1 << 16;
        const uint FLAG_OBJECT_AS_ID = 1 << 16;
        const int MAX_RECURSION_DEPTH = 1024;
        const int MAX_WRITE_RECURSION = 100;

        // ------------------------------------------------------------------ registry of value types from other assemblies
        sealed class Codec
        {
            public int Type;
            public Type Clr;
            public Func<object, double[]> To;
            public Func<double[], object> From;
            public Func<int, Array> NewArray;
        }

        static readonly Dictionary<Type, Codec> _byClr = new Dictionary<Type, Codec>();
        static readonly Dictionary<int, Codec> _byType = new Dictionary<int, Codec>();

        /// <summary>Maps a C# value type to a Godot type: toComponents gives the components in Godot's binary order
        /// (Color: r g b a; Rect2: x y w h; Transform2D: x.x x.y y.x y.y origin.x origin.y; Basis: by rows...),
        /// fromComponents builds the value back. Packed arrays of the type (PackedColorArray) become T[].</summary>
        public static void Register<T>(int godotType, Func<T, double[]> toComponents, Func<double[], T> fromComponents)
        {
            var c = new Codec
            {
                Type = godotType,
                Clr = typeof(T),
                To = o => toComponents((T)o),
                From = d => fromComponents(d),
                NewArray = n => new T[n],
            };
            lock (_byClr)
            {
                _byClr[typeof(T)] = c;
                _byType[godotType] = c;
            }
        }

        static Codec CodecOf(Type t)
        {
            lock (_byClr) return _byClr.TryGetValue(t, out var c) ? c : null;
        }

        static Codec CodecOf(int godotType)
        {
            lock (_byClr) return _byType.TryGetValue(godotType, out var c) ? c : null;
        }

        /// <summary>A value of a Godot math type from its components: the registered C# type, or a GValue.</summary>
        public static Var MakeValue(int godotType, double[] comps)
        {
            var c = CodecOf(godotType);
            if (c != null) return Var.Of(c.From(comps));
            return Var.Of(new GValue(godotType, comps));
        }

        /// <summary>A PackedColorArray / PackedVector4Array from 4 components per element: an array of the registered C#
        /// type (Col[]), or GValue[].</summary>
        public static Var MakePacked4(int elementType, IList<double> comps)
        {
            int n = comps.Count / 4;
            var codec = CodecOf(elementType);
            Array x = codec != null ? codec.NewArray(n) : new GValue[n];
            for (int i = 0; i < n; i++)
            {
                var c = new double[] { (float)comps[i * 4], (float)comps[i * 4 + 1], (float)comps[i * 4 + 2], (float)comps[i * 4 + 3] };
                x.SetValue(codec != null ? codec.From(c) : new GValue(elementType, c), i);
            }
            return Var.Of(x);
        }

        /// <summary>The Godot type number and components of a held value (registered type or GValue), or false.</summary>
        public static bool TryComponents(object o, out int godotType, out double[] comps)
        {
            if (o is GValue g) { godotType = g.Type; comps = g.C; return true; }
            if (o != null)
            {
                var c = CodecOf(o.GetType());
                if (c != null) { godotType = c.Type; comps = c.To(o); return true; }
            }
            godotType = 0;
            comps = null;
            return false;
        }

        /// <summary>Components of each Godot math type (0: not a math type).</summary>
        public static int ComponentCount(int t)
        {
            switch (t)
            {
                case GD.TYPE_VECTOR2: case GD.TYPE_VECTOR2I: return 2;
                case GD.TYPE_VECTOR3: case GD.TYPE_VECTOR3I: return 3;
                case GD.TYPE_RECT2: case GD.TYPE_RECT2I: case GD.TYPE_VECTOR4: case GD.TYPE_VECTOR4I:
                case GD.TYPE_PLANE: case GD.TYPE_QUATERNION: case GD.TYPE_COLOR: return 4;
                case GD.TYPE_TRANSFORM2D: case GD.TYPE_AABB: return 6;
                case GD.TYPE_BASIS: return 9;
                case GD.TYPE_TRANSFORM3D: return 12;
                case GD.TYPE_PROJECTION: return 16;
            }
            return 0;
        }

        public static bool IsIntType(int t) => t == GD.TYPE_VECTOR2I || t == GD.TYPE_RECT2I || t == GD.TYPE_VECTOR3I || t == GD.TYPE_VECTOR4I;

        static readonly string[] TextNames = {
            null, null, null, null, null, "Vector2", "Vector2i", "Rect2", "Rect2i", "Vector3", "Vector3i", "Transform2D",
            "Vector4", "Vector4i", "Plane", "Quaternion", "AABB", "Basis", "Transform3D", "Projection", "Color" };

        // ------------------------------------------------------------------ var_to_bytes
        sealed class Buf
        {
            public byte[] A = new byte[64];
            public int N;

            void Need(int k)
            {
                if (N + k > A.Length) Array.Resize(ref A, Math.Max(A.Length * 2, N + k));
            }

            public void U8(byte b) { Need(1); A[N++] = b; }

            public void U32(uint v)
            {
                Need(4);
                A[N] = (byte)v; A[N + 1] = (byte)(v >> 8); A[N + 2] = (byte)(v >> 16); A[N + 3] = (byte)(v >> 24);
                N += 4;
            }

            public void U64(ulong v) { U32((uint)v); U32((uint)(v >> 32)); }
            public void F32(float f) => U32(unchecked((uint)BitConverter.SingleToInt32Bits(f)));
            public void F64(double d) => U64(unchecked((ulong)BitConverter.DoubleToInt64Bits(d)));

            public void Bytes(byte[] b, int off, int len)
            {
                Need(len);
                Buffer.BlockCopy(b, off, A, N, len);
                N += len;
            }

            public void Pad4() { while ((N & 3) != 0) U8(0); }

            public byte[] ToArray()
            {
                var r = new byte[N];
                Buffer.BlockCopy(A, 0, r, 0, N);
                return r;
            }
        }

        static readonly UTF8Encoding Utf8Strict = new UTF8Encoding(false, true);
        static readonly UTF8Encoding Utf8Lenient = new UTF8Encoding(false, false);

        /// <summary>var_to_bytes(v): Godot's bytes (empty on error, as Godot).</summary>
        public static byte[] VarToBytes(Var v, bool fullObjects = false)
        {
            var w = new Buf();
            int err = Encode(v, w, fullObjects, 0);
            return err == GD.OK ? w.ToArray() : Array.Empty<byte>();
        }

        /// <summary>encode_variant: OK, or Godot's error (the buffer then holds a partial encoding).</summary>
        static int Encode(Var v, Buf w, bool full, int depth)
        {
            if (depth > MAX_RECURSION_DEPTH)
            {
                GD.PushError("Potential infinite recursion detected. Bailing.");
                return GD.ERR_OUT_OF_MEMORY;
            }
            switch (v.Type)
            {
                case VT.Nil: w.U32(GD.TYPE_NIL); return GD.OK;
                case VT.Bool: w.U32(GD.TYPE_BOOL); w.U32(v.Truthy ? 1u : 0u); return GD.OK;
                case VT.Int:
                    {
                        long x = v.AsLong();
                        if (x > int.MaxValue || x < int.MinValue) { w.U32(GD.TYPE_INT | FLAG_64); w.U64(unchecked((ulong)x)); }
                        else { w.U32(GD.TYPE_INT); w.U32(unchecked((uint)(int)x)); }
                        return GD.OK;
                    }
                case VT.Float:
                    {
                        double d = v.AsFloat();
                        float f = (float)d;
                        if ((double)f != d) { w.U32(GD.TYPE_FLOAT | FLAG_64); w.F64(d); }
                        else { w.U32(GD.TYPE_FLOAT); w.F32(f); }
                        return GD.OK;
                    }
                case VT.String: w.U32(GD.TYPE_STRING); EncStr(w, v.AsString()); return GD.OK;
                case VT.Vec2: { var p = v.AsVec2(); w.U32(GD.TYPE_VECTOR2); w.F32(p.x); w.F32(p.y); return GD.OK; }
                case VT.Vec2i: { var p = v.AsVec2i(); w.U32(GD.TYPE_VECTOR2I); w.U32(unchecked((uint)p.x)); w.U32(unchecked((uint)p.y)); return GD.OK; }
                case VT.Vec3: { var p = v.AsVec3(); w.U32(GD.TYPE_VECTOR3); w.F32(p.x); w.F32(p.y); w.F32(p.z); return GD.OK; }
                case VT.Dict:
                    {
                        var d = v.AsDict();
                        w.U32(GD.TYPE_DICTIONARY);
                        w.U32((uint)d.Size());
                        foreach (var kv in d.Pairs())
                        {
                            int e = Encode(kv.Key, w, full, depth + 1);
                            if (e != GD.OK) return e;
                            e = Encode(kv.Value, w, full, depth + 1);
                            if (e != GD.OK) return e;
                        }
                        return GD.OK;
                    }
                case VT.Arr:
                    {
                        var a = v.AsArr();
                        w.U32(GD.TYPE_ARRAY);
                        w.U32((uint)a.Size());
                        foreach (var x in a.List)
                        {
                            int e = Encode(x, w, full, depth + 1);
                            if (e != GD.OK) return e;
                        }
                        return GD.OK;
                    }
            }
            return EncodeObject(v.Obj, w, full, depth);
        }

        static int EncodeObject(object o, Buf w, bool full, int depth)
        {
            if (TryComponents(o, out int gt, out double[] comps))
            {
                w.U32((uint)gt);
                WriteComps(w, gt, comps);
                return GD.OK;
            }
            switch (o)
            {
                case byte[] b:
                    w.U32(GD.TYPE_PACKED_BYTE_ARRAY);
                    w.U32((uint)b.Length);
                    w.Bytes(b, 0, b.Length);
                    w.Pad4();
                    return GD.OK;
                case int[] ia: w.U32(GD.TYPE_PACKED_INT32_ARRAY); w.U32((uint)ia.Length); foreach (var x in ia) w.U32(unchecked((uint)x)); return GD.OK;
                case List<int> il: w.U32(GD.TYPE_PACKED_INT32_ARRAY); w.U32((uint)il.Count); foreach (var x in il) w.U32(unchecked((uint)x)); return GD.OK;
                case long[] la: w.U32(GD.TYPE_PACKED_INT64_ARRAY); w.U32((uint)la.Length); foreach (var x in la) w.U64(unchecked((ulong)x)); return GD.OK;
                case List<long> ll: w.U32(GD.TYPE_PACKED_INT64_ARRAY); w.U32((uint)ll.Count); foreach (var x in ll) w.U64(unchecked((ulong)x)); return GD.OK;
                case float[] fa: w.U32(GD.TYPE_PACKED_FLOAT32_ARRAY); w.U32((uint)fa.Length); foreach (var x in fa) w.F32(x); return GD.OK;
                case List<float> fl: w.U32(GD.TYPE_PACKED_FLOAT32_ARRAY); w.U32((uint)fl.Count); foreach (var x in fl) w.F32(x); return GD.OK;
                case double[] da: w.U32(GD.TYPE_PACKED_FLOAT64_ARRAY); w.U32((uint)da.Length); foreach (var x in da) w.F64(x); return GD.OK;
                case List<double> dl: w.U32(GD.TYPE_PACKED_FLOAT64_ARRAY); w.U32((uint)dl.Count); foreach (var x in dl) w.F64(x); return GD.OK;
                case string[] sa: EncStrings(w, sa); return GD.OK;
                case List<string> sl: EncStrings(w, sl); return GD.OK;
                case Vec2[] va: w.U32(GD.TYPE_PACKED_VECTOR2_ARRAY); w.U32((uint)va.Length); foreach (var p in va) { w.F32(p.x); w.F32(p.y); } return GD.OK;
                case List<Vec2> vl: w.U32(GD.TYPE_PACKED_VECTOR2_ARRAY); w.U32((uint)vl.Count); foreach (var p in vl) { w.F32(p.x); w.F32(p.y); } return GD.OK;
                case Vec3[] v3a: w.U32(GD.TYPE_PACKED_VECTOR3_ARRAY); w.U32((uint)v3a.Length); foreach (var p in v3a) { w.F32(p.x); w.F32(p.y); w.F32(p.z); } return GD.OK;
                case List<Vec3> v3l: w.U32(GD.TYPE_PACKED_VECTOR3_ARRAY); w.U32((uint)v3l.Count); foreach (var p in v3l) { w.F32(p.x); w.F32(p.y); w.F32(p.z); } return GD.OK;
                case Delegate _: w.U32(GD.TYPE_CALLABLE); return GD.OK;
                case IGodotObject go:
                    if (go.IsFreed) { w.U32(GD.TYPE_NIL); return GD.OK; }
                    if (full)
                    {
                        GD.PushError("var_to_bytes_with_objects: objects can't be serialized by the port.");
                        return GD.ERR_INVALID_PARAMETER;
                    }
                    w.U32(GD.TYPE_OBJECT | FLAG_OBJECT_AS_ID);
                    w.U64(go.GetInstanceId());
                    return GD.OK;
                case EncodedObjectAsID eo:
                    w.U32(GD.TYPE_OBJECT | FLAG_OBJECT_AS_ID);
                    w.U64(eo.ObjectId);
                    return GD.OK;
            }
            if (o is Array arr)
            {
                // PackedColorArray / PackedVector4Array: arrays of a registered type, or of GValues
                var et = arr.GetType().GetElementType();
                int pt = -1;
                var c = CodecOf(et);
                if (c != null && (c.Type == GD.TYPE_COLOR || c.Type == GD.TYPE_VECTOR4)) pt = c.Type;
                else if (et == typeof(GValue)) pt = arr.Length > 0 && ((GValue)arr.GetValue(0)).Type == GD.TYPE_VECTOR4 ? GD.TYPE_VECTOR4 : GD.TYPE_COLOR;
                if (pt >= 0)
                {
                    w.U32((uint)(pt == GD.TYPE_COLOR ? GD.TYPE_PACKED_COLOR_ARRAY : GD.TYPE_PACKED_VECTOR4_ARRAY));
                    w.U32((uint)arr.Length);
                    foreach (var e in arr)
                    {
                        TryComponents(e, out _, out double[] cc);
                        for (int i = 0; i < 4; i++) w.F32(cc != null && i < cc.Length ? (float)cc[i] : 0f);
                    }
                    return GD.OK;
                }
            }
            if (o is IEnumerable en && !(o is string))
            {
                // any other list goes as an Array of its elements
                var items = new List<Var>();
                foreach (var x in en) items.Add(Var.Of(x));
                w.U32(GD.TYPE_ARRAY);
                w.U32((uint)items.Count);
                foreach (var x in items)
                {
                    int e = Encode(x, w, full, depth + 1);
                    if (e != GD.OK) return e;
                }
                return GD.OK;
            }
            if (o == null) { w.U32(GD.TYPE_NIL); return GD.OK; }
            if (o is IGodotValue)
            {
                GD.PushError("var_to_bytes: no encoding registered for " + o.GetType().Name + " (GMarshal.Register; the GUI types register in PlatformHost.Init()).");
                return GD.ERR_BUG;
            }
            // a plain C# object: an Object with no instance id (decodes as null on the other side)
            w.U32(GD.TYPE_OBJECT | FLAG_OBJECT_AS_ID);
            w.U64(0);
            return GD.OK;
        }

        static void WriteComps(Buf w, int t, double[] c)
        {
            int n = ComponentCount(t);
            bool ints = IsIntType(t);
            for (int i = 0; i < n; i++)
            {
                double x = i < c.Length ? c[i] : 0;
                if (ints) w.U32(unchecked((uint)(int)x));
                else w.F32((float)x);
            }
        }

        static void EncStr(Buf w, string s)
        {
            var b = Encoding.UTF8.GetBytes(s ?? "");
            w.U32((uint)b.Length);
            w.Bytes(b, 0, b.Length);
            w.Pad4();
        }

        static void EncStrings(Buf w, IList<string> l)
        {
            w.U32(GD.TYPE_PACKED_STRING_ARRAY);
            w.U32((uint)l.Count);
            foreach (var s in l)
            {
                var b = Encoding.UTF8.GetBytes(s ?? "");
                w.U32((uint)(b.Length + 1));
                w.Bytes(b, 0, b.Length);
                w.U8(0);
                w.Pad4();
            }
        }

        // ------------------------------------------------------------------ bytes_to_var
        /// <summary>bytes_to_var(bytes): the value, or null when the bytes don't decode (Godot prints why).</summary>
        public static Var BytesToVar(byte[] b, bool allowObjects = false)
        {
            if (b == null) return Var.Nil;
            int err = DecodeVariant(b, 0, b.Length, out Var r, out _, allowObjects);
            return err == GD.OK ? r : Var.Nil;
        }

        /// <summary>decode_variant at offset with len bytes available: OK or Godot's error; used = Godot's r_len.</summary>
        public static int DecodeVariant(byte[] b, int offset, int len, out Var r, out int used, bool allowObjects = false)
        {
            int e = Dec(b, offset, len, out r, out used, allowObjects, 0);
            if (e != GD.OK) r = Var.Nil;
            return e;
        }

        static uint R32(byte[] b, int p) => (uint)(b[p] | (b[p + 1] << 8) | (b[p + 2] << 16) | (b[p + 3] << 24));
        static ulong R64(byte[] b, int p) => R32(b, p) | ((ulong)R32(b, p + 4) << 32);
        static float RF(byte[] b, int p) => BitConverter.Int32BitsToSingle(unchecked((int)R32(b, p)));
        static double RD(byte[] b, int p) => BitConverter.Int64BitsToDouble(unchecked((long)R64(b, p)));

        static int Fail(int err, string cond)
        {
            GD.PushError("Condition \"" + cond + "\" is true. Returning: " + ErrName(err));
            return err;
        }

        static string ErrName(int e)
        {
            switch (e)
            {
                case GD.ERR_INVALID_DATA: return "ERR_INVALID_DATA";
                case GD.ERR_FILE_EOF: return "ERR_FILE_EOF";
                case GD.ERR_UNAUTHORIZED: return "ERR_UNAUTHORIZED";
                case GD.ERR_OUT_OF_MEMORY: return "ERR_OUT_OF_MEMORY";
                case GD.ERR_UNAVAILABLE: return "ERR_UNAVAILABLE";
                case GD.ERR_BUG: return "ERR_BUG";
            }
            return e.ToString(CultureInfo.InvariantCulture);
        }

        // ERR_FAIL_MUL_OF(a, b): a < 0 || b <= 0 || a > INT_MAX / b
        static bool MulOverflows(int a, int b) => a < 0 || b <= 0 || a > int.MaxValue / b;

        static int DecStr(byte[] b, ref int p, ref int len, out string s)
        {
            s = null;
            if (len < 4) return Fail(GD.ERR_INVALID_DATA, "len < 4");
            int strlen = unchecked((int)R32(b, p));
            int pad = 0;
            if (strlen % 4 != 0) pad = 4 - strlen % 4;
            p += 4;
            len -= 4;
            if (pad < 0 || strlen < 0 || strlen > int.MaxValue - pad) return Fail(GD.ERR_FILE_EOF, "add overflow");
            if (strlen < 0 || strlen + pad > len) return Fail(GD.ERR_FILE_EOF, "strlen < 0 || strlen + pad > len");
            s = Utf8(b, p, strlen, out bool ok);
            if (!ok) return Fail(GD.ERR_INVALID_DATA, "str.append_utf8((const char *)buf, strlen) != OK");
            strlen += pad;
            p += strlen;
            len -= strlen;
            return GD.OK;
        }

        /// <summary>String::append_utf8: a leading BOM skipped, stops at a NUL byte; ok false on invalid UTF-8 (the
        /// bad bytes become U+FFFD, as Godot).</summary>
        public static string Utf8(byte[] b, int off, int len, out bool ok)
        {
            ok = true;
            if (len >= 3 && b[off] == 0xEF && b[off + 1] == 0xBB && b[off + 2] == 0xBF) { off += 3; len -= 3; }
            int end = off;
            while (end < off + len && b[end] != 0) end++;
            try { return Utf8Strict.GetString(b, off, end - off); }
            catch (ArgumentException)
            {
                ok = false;
                return Utf8Lenient.GetString(b, off, end - off);
            }
        }

        static int SkipContainerType(byte[] b, ref int p, ref int len, uint kind)
        {
            switch (kind)
            {
                case 0: return GD.OK;
                case 1:
                    {
                        if (len < 4) return Fail(GD.ERR_INVALID_DATA, "len < 4");
                        int bt = unchecked((int)R32(b, p));
                        p += 4;
                        len -= 4;
                        if (bt < 0 || bt >= GD.TYPE_MAX) return Fail(GD.ERR_INVALID_DATA, "bt out of range");
                        return GD.OK;
                    }
                default:
                    return DecStr(b, ref p, ref len, out _);
            }
        }

        static int Dec(byte[] b, int start, int avail, out Var r, out int used, bool allowObjects, int depth)
        {
            r = Var.Nil;
            used = 0;
            if (depth > MAX_RECURSION_DEPTH) return Fail(GD.ERR_OUT_OF_MEMORY, "Variant is too deep. Bailing.");
            int p = start, len = avail;
            if (len < 4) return Fail(GD.ERR_INVALID_DATA, "len < 4");
            uint header = R32(b, p);
            uint type = header & HEADER_TYPE_MASK;
            if (type >= GD.TYPE_MAX) return Fail(GD.ERR_INVALID_DATA, "(header & HEADER_TYPE_MASK) >= Variant::VARIANT_MAX");
            p += 4;
            len -= 4;
            bool f64 = (header & FLAG_64) != 0;
            int e;
            switch ((int)type)
            {
                case GD.TYPE_NIL: break;
                case GD.TYPE_BOOL:
                    if (len < 4) return Fail(GD.ERR_INVALID_DATA, "len < 4");
                    r = R32(b, p) != 0;
                    p += 4;
                    break;
                case GD.TYPE_INT:
                    if (f64)
                    {
                        if (len < 8) return Fail(GD.ERR_INVALID_DATA, "len < 8");
                        r = unchecked((long)R64(b, p));
                        p += 8;
                    }
                    else
                    {
                        if (len < 4) return Fail(GD.ERR_INVALID_DATA, "len < 4");
                        r = (long)unchecked((int)R32(b, p));
                        p += 4;
                    }
                    break;
                case GD.TYPE_FLOAT:
                    if (f64)
                    {
                        if (len < 8) return Fail(GD.ERR_INVALID_DATA, "len < sizeof(double)");
                        r = RD(b, p);
                        p += 8;
                    }
                    else
                    {
                        if (len < 4) return Fail(GD.ERR_INVALID_DATA, "len < sizeof(float)");
                        r = (double)RF(b, p);
                        p += 4;
                    }
                    break;
                case GD.TYPE_STRING:
                case GD.TYPE_STRING_NAME:
                    {
                        e = DecStr(b, ref p, ref len, out string s);
                        if (e != GD.OK) return e;
                        r = s;
                        break;
                    }
                case GD.TYPE_VECTOR2:
                case GD.TYPE_VECTOR2I:
                case GD.TYPE_VECTOR3:
                case GD.TYPE_RECT2:
                case GD.TYPE_RECT2I:
                case GD.TYPE_VECTOR3I:
                case GD.TYPE_VECTOR4:
                case GD.TYPE_VECTOR4I:
                case GD.TYPE_TRANSFORM2D:
                case GD.TYPE_PLANE:
                case GD.TYPE_QUATERNION:
                case GD.TYPE_AABB:
                case GD.TYPE_BASIS:
                case GD.TYPE_TRANSFORM3D:
                case GD.TYPE_PROJECTION:
                case GD.TYPE_COLOR:
                    {
                        int t = (int)type;
                        int n = ComponentCount(t);
                        bool ints = IsIntType(t);
                        int sz = ints || t == GD.TYPE_COLOR || !f64 ? 4 : 8;
                        if (len < n * sz) return Fail(GD.ERR_INVALID_DATA, "len < size");
                        var c = new double[n];
                        for (int i = 0; i < n; i++)
                        {
                            if (ints) c[i] = unchecked((int)R32(b, p + i * 4));
                            else if (sz == 8) c[i] = (float)RD(b, p + i * 8);      // (narrowed to real_t, as Godot)
                            else c[i] = RF(b, p + i * 4);
                        }
                        p += n * sz;
                        if (t == GD.TYPE_VECTOR2) r = new Vec2((float)c[0], (float)c[1]);
                        else if (t == GD.TYPE_VECTOR2I) r = new Vec2i((int)c[0], (int)c[1]);
                        else if (t == GD.TYPE_VECTOR3) r = new Vec3((float)c[0], (float)c[1], (float)c[2]);
                        else r = MakeValue(t, c);
                        break;
                    }
                case GD.TYPE_NODE_PATH:
                    {
                        if (len < 4) return Fail(GD.ERR_INVALID_DATA, "len < 4");
                        uint strlen = R32(b, p);
                        if ((strlen & 0x80000000) == 0) return Fail(GD.ERR_INVALID_DATA, "old NodePath format");
                        if (len < 12) return Fail(GD.ERR_INVALID_DATA, "len < 12");
                        uint namecount = strlen & 0x7FFFFFFF;
                        uint subnamecount = R32(b, p + 4);
                        uint flags = R32(b, p + 8);
                        p += 12;
                        len -= 12;
                        if ((flags & 2) != 0) subnamecount++;
                        uint total = namecount + subnamecount;
                        var sb = new StringBuilder();
                        if ((flags & 1) != 0) sb.Append('/');
                        for (uint i = 0; i < total; i++)
                        {
                            e = DecStr(b, ref p, ref len, out string s);
                            if (e != GD.OK) return e;
                            if (i < namecount) { if (i > 0) sb.Append('/'); }
                            else sb.Append(':');
                            sb.Append(s);
                        }
                        r = sb.ToString();
                        break;
                    }
                case GD.TYPE_RID:
                    if (len < 8) return Fail(GD.ERR_INVALID_DATA, "len < 8");
                    r = unchecked((long)R64(b, p));
                    p += 8;
                    break;
                case GD.TYPE_OBJECT:
                    if ((header & FLAG_OBJECT_AS_ID) != 0)
                    {
                        if (len < 8) return Fail(GD.ERR_INVALID_DATA, "len < 8");
                        ulong id = R64(b, p);
                        p += 8;
                        r = id == 0 ? Var.Nil : Var.Of(new EncodedObjectAsID { ObjectId = id });
                    }
                    else
                    {
                        if (!allowObjects) return Fail(GD.ERR_UNAUTHORIZED, "!p_allow_objects");
                        e = DecStr(b, ref p, ref len, out string cls);
                        if (e != GD.OK) return e;
                        if (cls.Length == 0) { r = Var.Nil; break; }
                        return Fail(GD.ERR_UNAVAILABLE, "objects can't be instantiated by the port");
                    }
                    break;
                case GD.TYPE_CALLABLE: break;
                case GD.TYPE_SIGNAL:
                    {
                        e = DecStr(b, ref p, ref len, out _);
                        if (e != GD.OK) return e;
                        if (len < 8) return Fail(GD.ERR_INVALID_DATA, "len < 8");
                        p += 8;
                        break;
                    }
                case GD.TYPE_DICTIONARY:
                    {
                        e = SkipContainerType(b, ref p, ref len, (header >> 16) & 3);
                        if (e != GD.OK) return e;
                        e = SkipContainerType(b, ref p, ref len, (header >> 18) & 3);
                        if (e != GD.OK) return e;
                        if (len < 4) return Fail(GD.ERR_INVALID_DATA, "len < 4");
                        int count = unchecked((int)(R32(b, p) & 0x7FFFFFFF));
                        p += 4;
                        len -= 4;
                        var d = new GDict();
                        for (int i = 0; i < count; i++)
                        {
                            e = Dec(b, p, len, out Var key, out int u, allowObjects, depth + 1);
                            if (e != GD.OK) { GD.PushError("Error when trying to decode Variant."); return e; }
                            p += u;
                            len -= u;
                            e = Dec(b, p, len, out Var val, out u, allowObjects, depth + 1);
                            if (e != GD.OK) { GD.PushError("Error when trying to decode Variant."); return e; }
                            p += u;
                            len -= u;
                            d[key] = val;
                        }
                        r = d;
                        break;
                    }
                case GD.TYPE_ARRAY:
                    {
                        e = SkipContainerType(b, ref p, ref len, (header >> 16) & 3);
                        if (e != GD.OK) return e;
                        if (len < 4) return Fail(GD.ERR_INVALID_DATA, "len < 4");
                        int count = unchecked((int)(R32(b, p) & 0x7FFFFFFF));
                        p += 4;
                        len -= 4;
                        var a = new GArray();
                        for (int i = 0; i < count; i++)
                        {
                            e = Dec(b, p, len, out Var el, out int u, allowObjects, depth + 1);
                            if (e != GD.OK) { GD.PushError("Error when trying to decode Variant."); return e; }
                            p += u;
                            len -= u;
                            a.Append(el);
                        }
                        r = a;
                        break;
                    }
                case GD.TYPE_PACKED_BYTE_ARRAY:
                    {
                        if (len < 4) return Fail(GD.ERR_INVALID_DATA, "len < 4");
                        int count = unchecked((int)R32(b, p));
                        p += 4;
                        len -= 4;
                        if (count < 0 || count > len) return Fail(GD.ERR_INVALID_DATA, "count < 0 || count > len");
                        var data = new byte[count];
                        Buffer.BlockCopy(b, p, data, 0, count);
                        r = Var.Of(data);
                        p += count;
                        if (count % 4 != 0) p += 4 - count % 4;
                        break;
                    }
                case GD.TYPE_PACKED_INT32_ARRAY:
                case GD.TYPE_PACKED_INT64_ARRAY:
                case GD.TYPE_PACKED_FLOAT32_ARRAY:
                case GD.TYPE_PACKED_FLOAT64_ARRAY:
                    {
                        if (len < 4) return Fail(GD.ERR_INVALID_DATA, "len < 4");
                        int count = unchecked((int)R32(b, p));
                        p += 4;
                        len -= 4;
                        int t = (int)type;
                        int sz = t == GD.TYPE_PACKED_INT32_ARRAY || t == GD.TYPE_PACKED_FLOAT32_ARRAY ? 4 : 8;
                        if (MulOverflows(count, sz)) return Fail(GD.ERR_INVALID_DATA, "mul overflow");
                        if (count < 0 || count * sz > len) return Fail(GD.ERR_INVALID_DATA, "count < 0 || count * size > len");
                        switch (t)
                        {
                            case GD.TYPE_PACKED_INT32_ARRAY: { var x = new int[count]; for (int i = 0; i < count; i++) x[i] = unchecked((int)R32(b, p + i * 4)); r = Var.Of(x); break; }
                            case GD.TYPE_PACKED_INT64_ARRAY: { var x = new long[count]; for (int i = 0; i < count; i++) x[i] = unchecked((long)R64(b, p + i * 8)); r = Var.Of(x); break; }
                            case GD.TYPE_PACKED_FLOAT32_ARRAY: { var x = new float[count]; for (int i = 0; i < count; i++) x[i] = RF(b, p + i * 4); r = Var.Of(x); break; }
                            default: { var x = new double[count]; for (int i = 0; i < count; i++) x[i] = RD(b, p + i * 8); r = Var.Of(x); break; }
                        }
                        p += count * sz;
                        break;
                    }
                case GD.TYPE_PACKED_STRING_ARRAY:
                    {
                        if (len < 4) return Fail(GD.ERR_INVALID_DATA, "len < 4");
                        int count = unchecked((int)R32(b, p));
                        p += 4;
                        len -= 4;
                        var l = new List<string>();
                        for (int i = 0; i < count; i++)
                        {
                            e = DecStr(b, ref p, ref len, out string s);
                            if (e != GD.OK) return e;
                            l.Add(s);
                        }
                        r = Var.Of(l.ToArray());
                        break;
                    }
                case GD.TYPE_PACKED_VECTOR2_ARRAY:
                case GD.TYPE_PACKED_VECTOR3_ARRAY:
                case GD.TYPE_PACKED_COLOR_ARRAY:
                case GD.TYPE_PACKED_VECTOR4_ARRAY:
                    {
                        if (len < 4) return Fail(GD.ERR_INVALID_DATA, "len < 4");
                        int count = unchecked((int)R32(b, p));
                        p += 4;
                        len -= 4;
                        int t = (int)type;
                        int n = t == GD.TYPE_PACKED_VECTOR2_ARRAY ? 2 : t == GD.TYPE_PACKED_VECTOR3_ARRAY ? 3 : 4;
                        int sz = f64 && t != GD.TYPE_PACKED_COLOR_ARRAY ? 8 : 4;
                        if (MulOverflows(count, n * sz)) return Fail(GD.ERR_INVALID_DATA, "mul overflow");
                        if (count < 0 || count * n * sz > len) return Fail(GD.ERR_INVALID_DATA, "count < 0 || count * size > len");
                        float C(int i, int k) => sz == 8 ? (float)RD(b, p + (i * n + k) * 8) : RF(b, p + (i * n + k) * 4);
                        if (t == GD.TYPE_PACKED_VECTOR2_ARRAY)
                        {
                            var x = new Vec2[count];
                            for (int i = 0; i < count; i++) x[i] = new Vec2(C(i, 0), C(i, 1));
                            r = Var.Of(x);
                        }
                        else if (t == GD.TYPE_PACKED_VECTOR3_ARRAY)
                        {
                            var x = new Vec3[count];
                            for (int i = 0; i < count; i++) x[i] = new Vec3(C(i, 0), C(i, 1), C(i, 2));
                            r = Var.Of(x);
                        }
                        else
                        {
                            var comps = new double[count * 4];
                            for (int i = 0; i < count; i++) for (int k = 0; k < 4; k++) comps[i * 4 + k] = C(i, k);
                            r = MakePacked4(t == GD.TYPE_PACKED_COLOR_ARRAY ? GD.TYPE_COLOR : GD.TYPE_VECTOR4, comps);
                        }
                        p += count * n * sz;
                        break;
                    }
                default:
                    return Fail(GD.ERR_BUG, "unknown type");
            }
            used = p - start;
            return GD.OK;
        }

        // ------------------------------------------------------------------ base64 (Marshalls)
        /// <summary>CryptoCore::b64_decode (mbedtls): strict alphabet and padding, line breaks allowed; false on bad input.</summary>
        public static bool B64Decode(string s, out byte[] r)
        {
            r = Array.Empty<byte>();
            if (string.IsNullOrEmpty(s)) return true;
            var sb = new StringBuilder(s.Length);
            foreach (char c in s)
            {
                if (c == '\r' || c == '\n' || c == ' ') continue;
                if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '+' || c == '/' || c == '=')) return false;
                sb.Append(c);
            }
            if (sb.Length % 4 != 0) return false;
            try { r = Convert.FromBase64String(sb.ToString()); return true; }
            catch (FormatException) { return false; }
        }

        public static string B64Encode(byte[] b) => b == null || b.Length == 0 ? "" : Convert.ToBase64String(b);

        // ------------------------------------------------------------------ var_to_str: VariantWriter (compat mode, as var_to_str and ConfigFile)
        /// <summary>var_to_str(v): Godot's text form (what ConfigFile and .tres files hold).</summary>
        public static string VarToStr(Var v)
        {
            var sb = new StringBuilder();
            Write(sb, v, 0);
            return sb.ToString();
        }

        /// <summary>rtos_fix: shortest round-trip digits; a double that is exactly a float is written as the float.</summary>
        public static string RtosFix(double v)
        {
            if (v == 0.0) return "0";
            if (double.IsNegativeInfinity(v)) return "inf_neg";
            if ((double)(float)v == v) return NumScientific((float)v);
            return NumScientific(v);
        }

        static void Write(StringBuilder sb, Var v, int rec)
        {
            switch (v.Type)
            {
                case VT.Nil: sb.Append("null"); return;
                case VT.Bool: sb.Append(v.Truthy ? "true" : "false"); return;
                case VT.Int: sb.Append(v.AsLong().ToString(CultureInfo.InvariantCulture)); return;
                case VT.Float:
                    {
                        string s = RtosFix(v.AsFloat());
                        if (s != "inf" && s != "-inf" && s != "nan" && s.IndexOf('.') < 0 && s.IndexOf('e') < 0 && s.IndexOf('E') < 0) s += ".0";
                        sb.Append(s);
                        return;
                    }
                case VT.String: sb.Append('"').Append(CEscapeMultiline(v.AsString())).Append('"'); return;
                case VT.Vec2: { var p = v.AsVec2(); sb.Append("Vector2(").Append(RtosFix(p.x)).Append(", ").Append(RtosFix(p.y)).Append(')'); return; }
                case VT.Vec2i: { var p = v.AsVec2i(); sb.Append("Vector2i(").Append(p.x.ToString(CultureInfo.InvariantCulture)).Append(", ").Append(p.y.ToString(CultureInfo.InvariantCulture)).Append(')'); return; }
                case VT.Vec3: { var p = v.AsVec3(); sb.Append("Vector3(").Append(RtosFix(p.x)).Append(", ").Append(RtosFix(p.y)).Append(", ").Append(RtosFix(p.z)).Append(')'); return; }
                case VT.Dict:
                    {
                        if (rec > MAX_WRITE_RECURSION) { GD.PushError("Max recursion reached"); sb.Append("{}"); return; }
                        var d = v.AsDict();
                        var keys = new List<Var>(d.Keys().List);
                        GSort.Sort(keys, StringLikeLess);
                        if (keys.Count == 0) { sb.Append("{}"); return; }
                        sb.Append("{\n");
                        for (int i = 0; i < keys.Count; i++)
                        {
                            Write(sb, keys[i], rec + 1);
                            sb.Append(": ");
                            Write(sb, d[keys[i]], rec + 1);
                            sb.Append(i + 1 < keys.Count ? ",\n" : "\n");
                        }
                        sb.Append('}');
                        return;
                    }
                case VT.Arr:
                    {
                        if (rec > MAX_WRITE_RECURSION) { GD.PushError("Max recursion reached"); sb.Append("[]"); return; }
                        sb.Append('[');
                        bool first = true;
                        foreach (var x in v.AsArr().List)
                        {
                            if (!first) sb.Append(", ");
                            first = false;
                            Write(sb, x, rec + 1);
                        }
                        sb.Append(']');
                        return;
                    }
            }
            WriteObject(sb, v.Obj);
        }

        static void WriteObject(StringBuilder sb, object o)
        {
            if (TryComponents(o, out int gt, out double[] c))
            {
                sb.Append(TextNames[gt]).Append('(');
                int n = ComponentCount(gt);
                bool ints = IsIntType(gt);
                for (int i = 0; i < n; i++)
                {
                    if (i > 0) sb.Append(", ");
                    double x = i < c.Length ? c[i] : 0;
                    sb.Append(ints ? ((int)x).ToString(CultureInfo.InvariantCulture) : RtosFix((float)x));
                }
                sb.Append(')');
                return;
            }
            switch (o)
            {
                case byte[] b: Join(sb, "PackedByteArray(", b.Length, i => b[i].ToString(CultureInfo.InvariantCulture)); return;
                case int[] ia: Join(sb, "PackedInt32Array(", ia.Length, i => ia[i].ToString(CultureInfo.InvariantCulture)); return;
                case List<int> il: Join(sb, "PackedInt32Array(", il.Count, i => il[i].ToString(CultureInfo.InvariantCulture)); return;
                case long[] la: Join(sb, "PackedInt64Array(", la.Length, i => la[i].ToString(CultureInfo.InvariantCulture)); return;
                case List<long> ll: Join(sb, "PackedInt64Array(", ll.Count, i => ll[i].ToString(CultureInfo.InvariantCulture)); return;
                case float[] fa: Join(sb, "PackedFloat32Array(", fa.Length, i => RtosFix(fa[i])); return;
                case List<float> fl: Join(sb, "PackedFloat32Array(", fl.Count, i => RtosFix(fl[i])); return;
                case double[] da: Join(sb, "PackedFloat64Array(", da.Length, i => RtosFix(da[i])); return;
                case List<double> dl: Join(sb, "PackedFloat64Array(", dl.Count, i => RtosFix(dl[i])); return;
                case string[] sa: Join(sb, "PackedStringArray(", sa.Length, i => "\"" + GStr.CEscape(sa[i] ?? "") + "\""); return;
                case List<string> sl: Join(sb, "PackedStringArray(", sl.Count, i => "\"" + GStr.CEscape(sl[i] ?? "") + "\""); return;
                case Vec2[] va: Join(sb, "PackedVector2Array(", va.Length, i => RtosFix(va[i].x) + ", " + RtosFix(va[i].y)); return;
                case List<Vec2> vl: Join(sb, "PackedVector2Array(", vl.Count, i => RtosFix(vl[i].x) + ", " + RtosFix(vl[i].y)); return;
                case Vec3[] v3: Join(sb, "PackedVector3Array(", v3.Length, i => RtosFix(v3[i].x) + ", " + RtosFix(v3[i].y) + ", " + RtosFix(v3[i].z)); return;
                case List<Vec3> v3l: Join(sb, "PackedVector3Array(", v3l.Count, i => RtosFix(v3l[i].x) + ", " + RtosFix(v3l[i].y) + ", " + RtosFix(v3l[i].z)); return;
                case Delegate _: sb.Append("Callable()"); return;
            }
            if (o is Array arr)
            {
                var et = arr.GetType().GetElementType();
                var codec = CodecOf(et);
                int t = codec != null ? codec.Type : et == typeof(GValue) && arr.Length > 0 ? ((GValue)arr.GetValue(0)).Type : et == typeof(GValue) ? GD.TYPE_COLOR : -1;
                if (t == GD.TYPE_COLOR || t == GD.TYPE_VECTOR4)
                {
                    Join(sb, t == GD.TYPE_COLOR ? "PackedColorArray(" : "PackedVector4Array(", arr.Length, i =>
                    {
                        TryComponents(arr.GetValue(i), out _, out double[] cc);
                        return RtosFix((float)cc[0]) + ", " + RtosFix((float)cc[1]) + ", " + RtosFix((float)cc[2]) + ", " + RtosFix((float)cc[3]);
                    });
                    return;
                }
            }
            // objects are not stored (Godot writes Object(Class,...) with its properties; freed or null: null)
            sb.Append("null");
        }

        static void Join(StringBuilder sb, string head, int n, Func<int, string> item)
        {
            sb.Append(head);
            for (int i = 0; i < n; i++)
            {
                if (i > 0) sb.Append(", ");
                sb.Append(item(i));
            }
            sb.Append(')');
        }

        public static string CEscapeMultiline(string s) => s.Replace("\\", "\\\\").Replace("\"", "\\\"");

        /// <summary>StringLikeVariantOrder: strings by code point, otherwise by type number, then Variant's `<`.</summary>
        static bool StringLikeLess(Var a, Var b)
        {
            if (a.IsString && b.IsString) return CodePointCompare(a.AsString(), b.AsString()) < 0;
            int ta = a.GodotType, tb = b.GodotType;
            if (ta != tb) return ta < tb;
            return Var.Less(a, b);
        }

        /// <summary>str_compare over code points (UTF-16 surrogates compared as the characters they make).</summary>
        public static int CodePointCompare(string a, string b)
        {
            int i = 0, j = 0;
            while (i < a.Length && j < b.Length)
            {
                int ca = char.IsHighSurrogate(a[i]) && i + 1 < a.Length && char.IsLowSurrogate(a[i + 1]) ? char.ConvertToUtf32(a[i], a[i + 1]) : a[i];
                int cb = char.IsHighSurrogate(b[j]) && j + 1 < b.Length && char.IsLowSurrogate(b[j + 1]) ? char.ConvertToUtf32(b[j], b[j + 1]) : b[j];
                if (ca != cb) return ca < cb ? -1 : 1;
                i += ca > 0xFFFF ? 2 : 1;
                j += cb > 0xFFFF ? 2 : 1;
            }
            if (i < a.Length) return 1;
            if (j < b.Length) return -1;
            return 0;
        }

        // ------------------------------------------------------------------ String::num_scientific (grisu2's layout)
        /// <summary>String::num_scientific(double): shortest round-trip digits, plain from 1e-4 up to 1e15, "1e+20"
        /// beyond; whole numbers without a ".0".</summary>
        public static string NumScientific(double v)
        {
            if (double.IsNaN(v) || double.IsInfinity(v)) return GFormat.Num(v, 0);
            bool neg = BitConverter.DoubleToInt64Bits(v) < 0;
            if (v == 0) return neg ? "-0" : "0";
            string digits = ShortestDigits(Math.Abs(v), out int e10, false);
            return Layout(neg, digits, e10);
        }

        /// <summary>String::num_scientific(float): the shortest digits that read back as the same float.</summary>
        public static string NumScientific(float v)
        {
            if (float.IsNaN(v) || float.IsInfinity(v)) return GFormat.Num(v, 0);
            bool neg = BitConverter.SingleToInt32Bits(v) < 0;
            if (v == 0) return neg ? "-0" : "0";
            string digits = ShortestDigits(Math.Abs((double)v), out int e10, true);
            return Layout(neg, digits, e10);
        }

        // digits d1..dk with value = d1..dk * 10^e10
        static string ShortestDigits(double a, out int e10, bool single)
        {
            int max = single ? 9 : 17;
            for (int p = 1; p <= max; p++)
            {
                string s = a.ToString("E" + (p - 1).ToString(CultureInfo.InvariantCulture), CultureInfo.InvariantCulture);
                bool same = single
                    ? float.Parse(s, NumberStyles.Float, CultureInfo.InvariantCulture) == (float)a
                    : double.Parse(s, NumberStyles.Float, CultureInfo.InvariantCulture) == a;
                if (!same && p < max) continue;
                int ep = s.IndexOf('E');
                string mant = s.Substring(0, ep).Replace(".", "");
                int x = int.Parse(s.Substring(ep + 1), NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture);
                string trimmed = mant.TrimEnd('0');
                if (trimmed.Length == 0) trimmed = "0";
                e10 = x - (trimmed.Length - 1);
                return trimmed;
            }
            e10 = 0;
            return "0";
        }

        static string Layout(bool neg, string d, int e10)
        {
            const int minExp = -4, maxExp = 15;
            int k = d.Length, n = k + e10;
            var sb = new StringBuilder();
            if (neg) sb.Append('-');
            if (k <= n && n <= maxExp) sb.Append(d).Append('0', n - k);
            else if (0 < n && n <= maxExp) sb.Append(d, 0, n).Append('.').Append(d, n, k - n);
            else if (minExp < n && n <= 0) sb.Append("0.").Append('0', -n).Append(d);
            else
            {
                sb.Append(d[0]);
                if (k > 1) sb.Append('.').Append(d, 1, k - 1);
                int ex = n - 1;
                sb.Append('e').Append(ex < 0 ? '-' : '+');
                ex = Math.Abs(ex);
                if (ex < 10) sb.Append('0');
                sb.Append(ex.ToString(CultureInfo.InvariantCulture));
            }
            return sb.ToString();
        }

        // ------------------------------------------------------------------ str() of the math types
        /// <summary>str() of a Godot math value from its components (Color "(r, g, b, a)", Rect2 "[P: (x, y), S: (w, h)]"...).</summary>
        public static string StrOf(int t, double[] c)
        {
            string R(int i) => GFormat.NumRealF((float)c[i], true);
            string Rn(int i) => GFormat.NumRealF((float)c[i], false);
            string I(int i) => ((int)c[i]).ToString(CultureInfo.InvariantCulture);
            string V2(int i) => "(" + R(i) + ", " + R(i + 1) + ")";
            string V3(int i) => "(" + R(i) + ", " + R(i + 1) + ", " + R(i + 2) + ")";
            switch (t)
            {
                case GD.TYPE_RECT2: return "[P: " + V2(0) + ", S: " + V2(2) + "]";
                case GD.TYPE_RECT2I: return "[P: (" + I(0) + ", " + I(1) + "), S: (" + I(2) + ", " + I(3) + ")]";
                case GD.TYPE_VECTOR3I: return "(" + I(0) + ", " + I(1) + ", " + I(2) + ")";
                case GD.TYPE_VECTOR4: return "(" + R(0) + ", " + R(1) + ", " + R(2) + ", " + R(3) + ")";
                case GD.TYPE_VECTOR4I: return "(" + I(0) + ", " + I(1) + ", " + I(2) + ", " + I(3) + ")";
                case GD.TYPE_PLANE: return "[N: " + V3(0) + ", D: " + Rn(3) + "]";
                case GD.TYPE_QUATERNION: return "(" + Rn(0) + ", " + Rn(1) + ", " + Rn(2) + ", " + Rn(3) + ")";
                case GD.TYPE_AABB: return "[P: " + V3(0) + ", S: " + V3(3) + "]";
                case GD.TYPE_TRANSFORM2D: return "[X: " + V2(0) + ", Y: " + V2(2) + ", O: " + V2(4) + "]";
                case GD.TYPE_BASIS:
                    return "[X: (" + R(0) + ", " + R(3) + ", " + R(6) + "), Y: (" + R(1) + ", " + R(4) + ", " + R(7) + "), Z: (" + R(2) + ", " + R(5) + ", " + R(8) + ")]";
                case GD.TYPE_TRANSFORM3D:
                    return "[X: (" + R(0) + ", " + R(3) + ", " + R(6) + "), Y: (" + R(1) + ", " + R(4) + ", " + R(7) + "), Z: (" + R(2) + ", " + R(5) + ", " + R(8) + "), O: " + V3(9) + "]";
                case GD.TYPE_COLOR:
                    return "(" + GFormat.Num((float)c[0], 4) + ", " + GFormat.Num((float)c[1], 4) + ", " + GFormat.Num((float)c[2], 4) + ", " + GFormat.Num((float)c[3], 4) + ")";
                case GD.TYPE_PROJECTION:
                    {
                        string V4(int i) => "(" + R(i) + ", " + R(i + 1) + ", " + R(i + 2) + ", " + R(i + 3) + ")";
                        return "[X: " + V4(0) + ", Y: " + V4(4) + ", Z: " + V4(8) + ", W: " + V4(12) + "]";
                    }
            }
            return "(" + string.Join(", ", Array.ConvertAll(c, x => GFormat.NumReal(x))) + ")";
        }

        // ------------------------------------------------------------------ str_to_var
        /// <summary>str_to_var(text): the value, or null when it doesn't parse.</summary>
        public static Var StrToVar(string s)
        {
            var p = new GVariantParser(s ?? "");
            int line = 1;
            p.Parse(out Var r, out _, ref line);
            return r;
        }
    }

    /// <summary>Godot's VariantParser (core/variant/variant_parser.cpp) over a string: values in the text format, and the
    /// "[section]" / "key=value" stream ConfigFile and project.godot are made of.</summary>
    public sealed class GVariantParser
    {
        public enum Tk { CurlyOpen, CurlyClose, BracketOpen, BracketClose, ParenOpen, ParenClose, Identifier, String, StringName, Number, Color, Colon, Comma, Period, Equal, Eof, Error }

        static readonly string[] TkName = { "'{'", "'}'", "'['", "']'", "'('", "')'", "identifier", "string", "string_name", "number", "color", "':'", "','", "'.'", "'='", "EOF", "ERROR" };

        public struct Token
        {
            public Tk Type;
            public Var Value;
        }

        readonly string _s;
        int _pos;
        bool _eof;
        char _saved;

        public GVariantParser(string text) { _s = text ?? ""; }

        char GetChar()
        {
            if (_pos < _s.Length) return _s[_pos++];
            _eof = true;
            return '\0';
        }

        bool IsEof => _eof;

        static bool IsHex(char c) => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
        static bool IsDigit(char c) => c >= '0' && c <= '9';
        static bool IsAlpha(char c) => (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');

        public int GetToken(out Token tk, ref int line, out string err)
        {
            tk = default;
            err = "";
            bool stringName = false;
            while (true)
            {
                char c;
                if (_saved != '\0') { c = _saved; _saved = '\0'; }
                else
                {
                    c = GetChar();
                    if (IsEof) { tk.Type = Tk.Eof; return GD.OK; }
                }
                switch (c)
                {
                    case '\n': line++; break;
                    case '\0': tk.Type = Tk.Eof; return GD.OK;
                    case '{': tk.Type = Tk.CurlyOpen; return GD.OK;
                    case '}': tk.Type = Tk.CurlyClose; return GD.OK;
                    case '[': tk.Type = Tk.BracketOpen; return GD.OK;
                    case ']': tk.Type = Tk.BracketClose; return GD.OK;
                    case '(': tk.Type = Tk.ParenOpen; return GD.OK;
                    case ')': tk.Type = Tk.ParenClose; return GD.OK;
                    case ':': tk.Type = Tk.Colon; return GD.OK;
                    case ';':
                        while (true)
                        {
                            char ch = GetChar();
                            if (IsEof) { tk.Type = Tk.Eof; return GD.OK; }
                            if (ch == '\n') { line++; break; }
                        }
                        break;
                    case ',': tk.Type = Tk.Comma; return GD.OK;
                    case '.': tk.Type = Tk.Period; return GD.OK;
                    case '=': tk.Type = Tk.Equal; return GD.OK;
                    case '#':
                        {
                            var cs = new StringBuilder("#");
                            while (true)
                            {
                                char ch = GetChar();
                                if (IsEof) { tk.Type = Tk.Eof; return GD.OK; }
                                if (IsHex(ch)) cs.Append(ch);
                                else { _saved = ch; break; }
                            }
                            tk.Value = HtmlColor(cs.ToString());
                            tk.Type = Tk.Color;
                            return GD.OK;
                        }
                    case '@':
                    case '&':
                        c = GetChar();
                        if (c != '"')
                        {
                            err = "Expected '\"' after '&'";
                            tk.Type = Tk.Error;
                            return GD.ERR_PARSE_ERROR;
                        }
                        stringName = true;
                        goto case '"';
                    case '"':
                        {
                            var str = new StringBuilder();
                            int prev = 0;
                            while (true)
                            {
                                char ch = GetChar();
                                if (ch == '\0') { err = "Unterminated string"; tk.Type = Tk.Error; return GD.ERR_PARSE_ERROR; }
                                if (ch == '"') break;
                                if (ch == '\\')
                                {
                                    char next = GetChar();
                                    if (next == '\0') { err = "Unterminated string"; tk.Type = Tk.Error; return GD.ERR_PARSE_ERROR; }
                                    int res;
                                    switch (next)
                                    {
                                        case 'b': res = 8; break;
                                        case 't': res = 9; break;
                                        case 'n': res = 10; break;
                                        case 'f': res = 12; break;
                                        case 'r': res = 13; break;
                                        case 'U':
                                        case 'u':
                                            {
                                                int hexLen = next == 'U' ? 6 : 4;
                                                res = 0;
                                                for (int j = 0; j < hexLen; j++)
                                                {
                                                    char hc = GetChar();
                                                    if (hc == '\0') { err = "Unterminated string"; tk.Type = Tk.Error; return GD.ERR_PARSE_ERROR; }
                                                    if (!IsHex(hc)) { err = "Malformed hex constant in string"; tk.Type = Tk.Error; return GD.ERR_PARSE_ERROR; }
                                                    int v = IsDigit(hc) ? hc - '0' : hc >= 'a' ? hc - 'a' + 10 : hc - 'A' + 10;
                                                    res = (res << 4) | v;
                                                }
                                                break;
                                            }
                                        default: res = next; break;
                                    }
                                    if ((res & 0xfffffc00) == 0xd800)
                                    {
                                        if (prev == 0) { prev = res; continue; }
                                        err = "Invalid UTF-16 sequence in string, unpaired lead surrogate";
                                        tk.Type = Tk.Error;
                                        return GD.ERR_PARSE_ERROR;
                                    }
                                    else if ((res & 0xfffffc00) == 0xdc00)
                                    {
                                        if (prev == 0)
                                        {
                                            err = "Invalid UTF-16 sequence in string, unpaired trail surrogate";
                                            tk.Type = Tk.Error;
                                            return GD.ERR_PARSE_ERROR;
                                        }
                                        res = (prev << 10) + res - ((0xd800 << 10) + 0xdc00 - 0x10000);
                                        prev = 0;
                                    }
                                    if (prev != 0)
                                    {
                                        err = "Invalid UTF-16 sequence in string, unpaired lead surrogate";
                                        tk.Type = Tk.Error;
                                        return GD.ERR_PARSE_ERROR;
                                    }
                                    if (res > 0x10FFFF || (res >= 0xD800 && res <= 0xDFFF)) str.Append('�');
                                    else str.Append(char.ConvertFromUtf32(res));
                                }
                                else
                                {
                                    if (prev != 0)
                                    {
                                        err = "Invalid UTF-16 sequence in string, unpaired lead surrogate";
                                        tk.Type = Tk.Error;
                                        return GD.ERR_PARSE_ERROR;
                                    }
                                    if (ch == '\n') line++;
                                    str.Append(ch);
                                }
                            }
                            if (prev != 0)
                            {
                                err = "Invalid UTF-16 sequence in string, unpaired lead surrogate";
                                tk.Type = Tk.Error;
                                return GD.ERR_PARSE_ERROR;
                            }
                            tk.Type = stringName ? Tk.StringName : Tk.String;
                            tk.Value = str.ToString();
                            return GD.OK;
                        }
                    default:
                        {
                            if (c <= 32) break;
                            var text = new StringBuilder();
                            if (c == '-')
                            {
                                text.Append('-');
                                c = GetChar();
                            }
                            if (c >= '0' && c <= '9')
                            {
                                const int INT = 1, DEC = 2, EXP = 3, DONE = 4;
                                int reading = INT;
                                bool expSign = false, expBeg = false, isFloat = false;
                                while (true)
                                {
                                    switch (reading)
                                    {
                                        case INT:
                                            if (IsDigit(c)) { }
                                            else if (c == '.') { reading = DEC; isFloat = true; }
                                            else if (c == 'e' || c == 'E') { reading = EXP; isFloat = true; }
                                            else reading = DONE;
                                            break;
                                        case DEC:
                                            if (IsDigit(c)) { }
                                            else if (c == 'e' || c == 'E') reading = EXP;
                                            else reading = DONE;
                                            break;
                                        case EXP:
                                            if (IsDigit(c)) expBeg = true;
                                            else if ((c == '-' || c == '+') && !expSign && !expBeg) expSign = true;
                                            else reading = DONE;
                                            break;
                                    }
                                    if (reading == DONE) break;
                                    text.Append(c);
                                    c = GetChar();
                                }
                                _saved = c;
                                tk.Type = Tk.Number;
                                string t = text.ToString();
                                if (isFloat) tk.Value = GStr.Strtod(t, 0, out _);
                                else tk.Value = ToInt(t);
                                return GD.OK;
                            }
                            if (IsAlpha(c) || c == '_')
                            {
                                bool first = true;
                                while (IsAlpha(c) || c == '_' || (!first && IsDigit(c)))
                                {
                                    text.Append(c);
                                    c = GetChar();
                                    first = false;
                                }
                                _saved = c;
                                tk.Type = Tk.Identifier;
                                tk.Value = text.ToString();
                                return GD.OK;
                            }
                            err = "Unexpected character";
                            tk.Type = Tk.Error;
                            return GD.ERR_PARSE_ERROR;
                        }
                }
            }
        }

        /// <summary>String::to_int(const char32_t *): sign, digits, stops at anything else.</summary>
        static long ToInt(string s)
        {
            long integer = 0, sign = 1;
            int i = 0;
            if (i < s.Length && s[i] == '-') { sign = -1; i++; }
            else if (i < s.Length && s[i] == '+') i++;
            for (; i < s.Length && IsDigit(s[i]); i++)
            {
                if (integer > long.MaxValue / 10)
                {
                    GD.PushError("Cannot represent " + s + " as a 64-bit signed integer, since the value is " + (sign == 1 ? "too large." : "too small."));
                    return sign == 1 ? long.MaxValue : long.MinValue;
                }
                integer = unchecked(integer * 10 + (s[i] - '0'));
            }
            return unchecked(sign * integer);
        }

        /// <summary>Color::html for "#rgb", "#rgba", "#rrggbb", "#rrggbbaa" (an invalid one is Color(), as Godot).</summary>
        static Var HtmlColor(string h)
        {
            string c = h.StartsWith("#", StringComparison.Ordinal) ? h.Substring(1) : h;
            double[] comps = null;
            int Hex(int i, int n) => Convert.ToInt32(c.Substring(i, n), 16);
            if (c.Length == 3 || c.Length == 4)
            {
                comps = new double[4];
                for (int i = 0; i < 4; i++) comps[i] = i < c.Length ? (float)Hex(i, 1) / 15f : 1.0;
            }
            else if (c.Length == 6 || c.Length == 8)
            {
                comps = new double[4];
                for (int i = 0; i < 4; i++) comps[i] = i * 2 < c.Length ? (float)Hex(i * 2, 2) / 255f : 1.0;
            }
            if (comps == null)
            {
                GD.PushError("Invalid color code: " + h + ".");
                comps = new double[] { 0, 0, 0, 1 };
            }
            return GMarshal.MakeValue(GD.TYPE_COLOR, comps);
        }

        static double StorFix(string s)
        {
            if (s == "inf") return double.PositiveInfinity;
            if (s == "-inf" || s == "inf_neg") return double.NegativeInfinity;
            if (s == "nan") return double.NaN;
            return -1;
        }

        int ParseConstruct(List<Var> args, ref int line, out string err)
        {
            GetToken(out Token tk, ref line, out err);
            if (tk.Type != Tk.ParenOpen) { err = "Expected '(' in constructor"; return GD.ERR_PARSE_ERROR; }
            bool first = true;
            while (true)
            {
                if (!first)
                {
                    GetToken(out tk, ref line, out err);
                    if (tk.Type == Tk.Comma) { }
                    else if (tk.Type == Tk.ParenClose) break;
                    else { err = "Expected ',' or ')' in constructor"; return GD.ERR_PARSE_ERROR; }
                }
                GetToken(out tk, ref line, out err);
                if (first && tk.Type == Tk.ParenClose) break;
                if (tk.Type != Tk.Number)
                {
                    bool valid = false;
                    if (tk.Type == Tk.Identifier)
                    {
                        double real = StorFix(tk.Value.AsString());
                        if (real != -1) { tk.Type = Tk.Number; tk.Value = real; valid = true; }
                    }
                    if (!valid) { err = "Expected float in constructor"; return GD.ERR_PARSE_ERROR; }
                }
                args.Add(tk.Value);
                first = false;
            }
            return GD.OK;
        }

        int ParseByteArray(List<byte> r, ref int line, out string err)
        {
            GetToken(out Token tk, ref line, out err);
            if (tk.Type != Tk.ParenOpen) { err = "Expected '(' in constructor"; return GD.ERR_PARSE_ERROR; }
            GetToken(out tk, ref line, out err);
            if (tk.Type == Tk.String)
            {
                if (!GMarshal.B64Decode(tk.Value.AsString(), out byte[] bytes)) { err = "Invalid base64-encoded string"; return GD.ERR_PARSE_ERROR; }
                r.AddRange(bytes);
                GetToken(out tk, ref line, out err);
                if (tk.Type != Tk.ParenClose) { err = "Expected ')' in constructor"; return GD.ERR_PARSE_ERROR; }
            }
            else if (tk.Type == Tk.Number || tk.Type == Tk.Identifier)
            {
                while (true)
                {
                    if (tk.Type != Tk.Number)
                    {
                        bool valid = false;
                        if (tk.Type == Tk.Identifier)
                        {
                            double real = StorFix(tk.Value.AsString());
                            if (real != -1) { tk.Type = Tk.Number; tk.Value = real; valid = true; }
                        }
                        if (!valid) { err = "Expected number in constructor"; return GD.ERR_PARSE_ERROR; }
                    }
                    r.Add(unchecked((byte)tk.Value.AsLong()));
                    GetToken(out tk, ref line, out err);
                    if (tk.Type == Tk.Comma) { }
                    else if (tk.Type == Tk.ParenClose) break;
                    else { err = "Expected ',' or ')' in constructor"; return GD.ERR_PARSE_ERROR; }
                    GetToken(out tk, ref line, out err);
                }
            }
            else if (tk.Type == Tk.ParenClose) return GD.OK;
            else { err = "Expected base64 string, or list of numbers in constructor"; return GD.ERR_PARSE_ERROR; }
            return GD.OK;
        }

        static readonly Dictionary<string, int> MathTypes = new Dictionary<string, int>
        {
            { "Rect2", GD.TYPE_RECT2 }, { "Rect2i", GD.TYPE_RECT2I }, { "Vector3i", GD.TYPE_VECTOR3I }, { "Vector4", GD.TYPE_VECTOR4 },
            { "Vector4i", GD.TYPE_VECTOR4I }, { "Transform2D", GD.TYPE_TRANSFORM2D }, { "Matrix32", GD.TYPE_TRANSFORM2D },
            { "Plane", GD.TYPE_PLANE }, { "Quaternion", GD.TYPE_QUATERNION }, { "Quat", GD.TYPE_QUATERNION }, { "AABB", GD.TYPE_AABB },
            { "Rect3", GD.TYPE_AABB }, { "Basis", GD.TYPE_BASIS }, { "Matrix3", GD.TYPE_BASIS }, { "Transform3D", GD.TYPE_TRANSFORM3D },
            { "Transform", GD.TYPE_TRANSFORM3D }, { "Projection", GD.TYPE_PROJECTION }, { "Color", GD.TYPE_COLOR },
        };

        static double Real(Var v) => (float)v.AsFloat();
        static int Int32(Var v) => unchecked((int)v.AsLong());

        int ExpectParen(Tk t, string msg, ref int line, out string err)
        {
            GetToken(out Token tk, ref line, out err);
            if (tk.Type != t) { err = msg; return GD.ERR_PARSE_ERROR; }
            return GD.OK;
        }

        /// <summary>parse_value: the value starting at token tk.</summary>
        public int ParseValue(Token tk, out Var value, ref int line, out string err)
        {
            value = Var.Nil;
            err = "";
            switch (tk.Type)
            {
                case Tk.CurlyOpen:
                    {
                        var d = new GDict();
                        int e = ParseDictionary(d, ref line, out err);
                        if (e != GD.OK) return e;
                        value = d;
                        return GD.OK;
                    }
                case Tk.BracketOpen:
                    {
                        var a = new GArray();
                        int e = ParseArray(a, ref line, out err);
                        if (e != GD.OK) return e;
                        value = a;
                        return GD.OK;
                    }
                case Tk.Number:
                case Tk.String:
                case Tk.StringName:
                case Tk.Color:
                    value = tk.Value;
                    return GD.OK;
                case Tk.Identifier:
                    break;
                default:
                    err = "Expected value, got '" + TkName[(int)tk.Type] + "'";
                    return GD.ERR_PARSE_ERROR;
            }
            string id = tk.Value.AsString();
            switch (id)
            {
                case "true": value = true; return GD.OK;
                case "false": value = false; return GD.OK;
                case "null":
                case "nil": value = Var.Nil; return GD.OK;
                case "inf": value = double.PositiveInfinity; return GD.OK;
                case "-inf":
                case "inf_neg": value = double.NegativeInfinity; return GD.OK;
                case "nan": value = double.NaN; return GD.OK;
            }
            if (id == "Vector2" || id == "Vector2i" || id == "Vector3" || MathTypes.ContainsKey(id))
            {
                var args = new List<Var>();
                int e = ParseConstruct(args, ref line, out err);
                if (e != GD.OK) return e;
                int t = id == "Vector2" ? GD.TYPE_VECTOR2 : id == "Vector2i" ? GD.TYPE_VECTOR2I : id == "Vector3" ? GD.TYPE_VECTOR3 : MathTypes[id];
                int n = GMarshal.ComponentCount(t);
                if (args.Count != n) { err = "Expected " + n + " arguments for constructor"; return GD.ERR_PARSE_ERROR; }
                bool ints = GMarshal.IsIntType(t);
                var c = new double[n];
                for (int i = 0; i < n; i++) c[i] = ints ? Int32(args[i]) : Real(args[i]);
                if (t == GD.TYPE_VECTOR2) value = new Vec2((float)c[0], (float)c[1]);
                else if (t == GD.TYPE_VECTOR2I) value = new Vec2i((int)c[0], (int)c[1]);
                else if (t == GD.TYPE_VECTOR3) value = new Vec3((float)c[0], (float)c[1], (float)c[2]);
                else value = GMarshal.MakeValue(t, c);
                return GD.OK;
            }
            switch (id)
            {
                case "NodePath":
                    {
                        int e = ExpectParen(Tk.ParenOpen, "Expected '('", ref line, out err);
                        if (e != GD.OK) return e;
                        GetToken(out Token t2, ref line, out err);
                        if (t2.Type != Tk.String) { err = "Expected string as argument for NodePath()"; return GD.ERR_PARSE_ERROR; }
                        value = t2.Value;
                        return ExpectParen(Tk.ParenClose, "Expected ')'", ref line, out err);
                    }
                case "RID":
                    {
                        int e = ExpectParen(Tk.ParenOpen, "Expected '('", ref line, out err);
                        if (e != GD.OK) return e;
                        GetToken(out Token t2, ref line, out err);
                        if (t2.Type == Tk.ParenClose) { value = 0L; return GD.OK; }
                        if (t2.Type != Tk.Number) { err = "Expected number as argument or ')'"; return GD.ERR_PARSE_ERROR; }
                        value = t2.Value.AsLong();
                        return ExpectParen(Tk.ParenClose, "Expected ')'", ref line, out err);
                    }
                case "Signal":
                case "Callable":
                    {
                        int e = ExpectParen(Tk.ParenOpen, "Expected '('", ref line, out err);
                        if (e != GD.OK) return e;
                        value = Var.Nil;
                        return ExpectParen(Tk.ParenClose, "Expected ')'", ref line, out err);
                    }
                case "Dictionary":
                    {
                        // Dictionary[KeyType, ValueType]({...}): the types are read and dropped (GDict is untyped)
                        int e = ExpectParen(Tk.BracketOpen, "Expected '['", ref line, out err);
                        if (e != GD.OK) return e;
                        GetToken(out Token t2, ref line, out err);
                        if (t2.Type != Tk.Identifier) { err = "Expected type identifier for key"; return GD.ERR_PARSE_ERROR; }
                        e = ExpectParen(Tk.Comma, "Expected ',' after key type", ref line, out err);
                        if (e != GD.OK) return e;
                        GetToken(out t2, ref line, out err);
                        if (t2.Type != Tk.Identifier) { err = "Expected type identifier for value"; return GD.ERR_PARSE_ERROR; }
                        e = ExpectParen(Tk.BracketClose, "Expected ']'", ref line, out err);
                        if (e != GD.OK) return e;
                        e = ExpectParen(Tk.ParenOpen, "Expected '('", ref line, out err);
                        if (e != GD.OK) return e;
                        e = ExpectParen(Tk.CurlyOpen, "Expected '{'", ref line, out err);
                        if (e != GD.OK) return e;
                        var d = new GDict();
                        e = ParseDictionary(d, ref line, out err);
                        if (e != GD.OK) return e;
                        e = ExpectParen(Tk.ParenClose, "Expected ')'", ref line, out err);
                        if (e != GD.OK) return e;
                        value = d;
                        return GD.OK;
                    }
                case "Array":
                    {
                        int e = ExpectParen(Tk.BracketOpen, "Expected '['", ref line, out err);
                        if (e != GD.OK) return e;
                        GetToken(out Token t2, ref line, out err);
                        if (t2.Type != Tk.Identifier) { err = "Expected type identifier"; return GD.ERR_PARSE_ERROR; }
                        e = ExpectParen(Tk.BracketClose, "Expected ']'", ref line, out err);
                        if (e != GD.OK) return e;
                        e = ExpectParen(Tk.ParenOpen, "Expected '('", ref line, out err);
                        if (e != GD.OK) return e;
                        e = ExpectParen(Tk.BracketOpen, "Expected '['", ref line, out err);
                        if (e != GD.OK) return e;
                        var a = new GArray();
                        e = ParseArray(a, ref line, out err);
                        if (e != GD.OK) return e;
                        e = ExpectParen(Tk.ParenClose, "Expected ')'", ref line, out err);
                        if (e != GD.OK) return e;
                        value = a;
                        return GD.OK;
                    }
                case "PackedByteArray":
                case "PoolByteArray":
                case "ByteArray":
                    {
                        var r = new List<byte>();
                        int e = ParseByteArray(r, ref line, out err);
                        if (e != GD.OK) return e;
                        value = Var.Of(r.ToArray());
                        return GD.OK;
                    }
                case "PackedStringArray":
                case "PoolStringArray":
                case "StringArray":
                    {
                        int e = ExpectParen(Tk.ParenOpen, "Expected '('", ref line, out err);
                        if (e != GD.OK) return e;
                        var cs = new List<string>();
                        bool first = true;
                        while (true)
                        {
                            Token t2;
                            if (!first)
                            {
                                GetToken(out t2, ref line, out err);
                                if (t2.Type == Tk.Comma) { }
                                else if (t2.Type == Tk.ParenClose) break;
                                else { err = "Expected ',' or ')'"; return GD.ERR_PARSE_ERROR; }
                            }
                            GetToken(out t2, ref line, out err);
                            if (t2.Type == Tk.ParenClose) break;
                            if (t2.Type != Tk.String) { err = "Expected string"; return GD.ERR_PARSE_ERROR; }
                            first = false;
                            cs.Add(t2.Value.AsString());
                        }
                        value = Var.Of(cs.ToArray());
                        return GD.OK;
                    }
            }
            int packed = -1;
            switch (id)
            {
                case "PackedInt32Array": case "PackedIntArray": case "PoolIntArray": case "IntArray": packed = GD.TYPE_PACKED_INT32_ARRAY; break;
                case "PackedInt64Array": packed = GD.TYPE_PACKED_INT64_ARRAY; break;
                case "PackedFloat32Array": case "PackedRealArray": case "PoolRealArray": case "FloatArray": packed = GD.TYPE_PACKED_FLOAT32_ARRAY; break;
                case "PackedFloat64Array": packed = GD.TYPE_PACKED_FLOAT64_ARRAY; break;
                case "PackedVector2Array": case "PoolVector2Array": case "Vector2Array": packed = GD.TYPE_PACKED_VECTOR2_ARRAY; break;
                case "PackedVector3Array": case "PoolVector3Array": case "Vector3Array": packed = GD.TYPE_PACKED_VECTOR3_ARRAY; break;
                case "PackedVector4Array": case "PoolVector4Array": case "Vector4Array": packed = GD.TYPE_PACKED_VECTOR4_ARRAY; break;
                case "PackedColorArray": case "PoolColorArray": case "ColorArray": packed = GD.TYPE_PACKED_COLOR_ARRAY; break;
            }
            if (packed >= 0)
            {
                var args = new List<Var>();
                int e = ParseConstruct(args, ref line, out err);
                if (e != GD.OK) return e;
                switch (packed)
                {
                    case GD.TYPE_PACKED_INT32_ARRAY: value = Var.Of(args.ConvertAll(Int32).ToArray()); break;
                    case GD.TYPE_PACKED_INT64_ARRAY: value = Var.Of(args.ConvertAll(a => a.AsLong()).ToArray()); break;
                    case GD.TYPE_PACKED_FLOAT32_ARRAY: value = Var.Of(args.ConvertAll(a => (float)a.AsFloat()).ToArray()); break;
                    case GD.TYPE_PACKED_FLOAT64_ARRAY: value = Var.Of(args.ConvertAll(a => a.AsFloat()).ToArray()); break;
                    case GD.TYPE_PACKED_VECTOR2_ARRAY:
                        {
                            var r = new Vec2[args.Count / 2];
                            for (int i = 0; i < r.Length; i++) r[i] = new Vec2((float)args[i * 2].AsFloat(), (float)args[i * 2 + 1].AsFloat());
                            value = Var.Of(r);
                            break;
                        }
                    case GD.TYPE_PACKED_VECTOR3_ARRAY:
                        {
                            var r = new Vec3[args.Count / 3];
                            for (int i = 0; i < r.Length; i++) r[i] = new Vec3((float)args[i * 3].AsFloat(), (float)args[i * 3 + 1].AsFloat(), (float)args[i * 3 + 2].AsFloat());
                            value = Var.Of(r);
                            break;
                        }
                    default:
                        value = GMarshal.MakePacked4(packed == GD.TYPE_PACKED_COLOR_ARRAY ? GD.TYPE_COLOR : GD.TYPE_VECTOR4, args.ConvertAll(a => a.AsFloat()));
                        break;
                }
                return GD.OK;
            }
            if (id == "Object" || id == "Resource" || id == "SubResource" || id == "ExtResource")
            {
                err = "Can't instantiate " + id + "() in the port";
                return GD.ERR_PARSE_ERROR;
            }
            err = "Unexpected identifier '" + id + "'";
            return GD.ERR_PARSE_ERROR;
        }

        int ParseArray(GArray array, ref int line, out string err)
        {
            bool needComma = false;
            err = "";
            while (true)
            {
                if (IsEof) { err = "Unexpected EOF while parsing array"; return GD.ERR_FILE_CORRUPT; }
                int e = GetToken(out Token tk, ref line, out err);
                if (e != GD.OK) return e;
                if (tk.Type == Tk.BracketClose) return GD.OK;
                if (needComma)
                {
                    if (tk.Type != Tk.Comma) { err = "Expected ','"; return GD.ERR_PARSE_ERROR; }
                    needComma = false;
                    continue;
                }
                e = ParseValue(tk, out Var v, ref line, out err);
                if (e != GD.OK) return e;
                array.Append(v);
                needComma = true;
            }
        }

        int ParseDictionary(GDict obj, ref int line, out string err)
        {
            bool atKey = true, needComma = false;
            Var key = Var.Nil;
            err = "";
            while (true)
            {
                if (IsEof) { err = "Unexpected EOF while parsing dictionary"; return GD.ERR_FILE_CORRUPT; }
                if (atKey)
                {
                    int e = GetToken(out Token tk, ref line, out err);
                    if (e != GD.OK) return e;
                    if (tk.Type == Tk.CurlyClose) return GD.OK;
                    if (needComma)
                    {
                        if (tk.Type != Tk.Comma) { err = "Expected '}' or ','"; return GD.ERR_PARSE_ERROR; }
                        needComma = false;
                        continue;
                    }
                    e = ParseValue(tk, out key, ref line, out err);
                    if (e != GD.OK) return e;
                    e = GetToken(out tk, ref line, out err);
                    if (e != GD.OK) return e;
                    if (tk.Type != Tk.Colon) { err = "Expected ':'"; return GD.ERR_PARSE_ERROR; }
                    atKey = false;
                }
                else
                {
                    int e = GetToken(out Token tk, ref line, out err);
                    if (e != GD.OK) return e;
                    e = ParseValue(tk, out Var v, ref line, out err);
                    if (e != GD.OK && e != GD.ERR_FILE_MISSING_DEPENDENCIES) return e;
                    obj[key] = v;
                    needComma = true;
                    atKey = true;
                }
            }
        }

        /// <summary>VariantParser::parse: one value (ERR_FILE_EOF on empty text).</summary>
        public int Parse(out Var value, out string err, ref int line)
        {
            value = Var.Nil;
            int e = GetToken(out Token tk, ref line, out err);
            if (e != GD.OK) return e;
            if (tk.Type == Tk.Eof) return GD.ERR_FILE_EOF;
            e = ParseValue(tk, out value, ref line, out err);
            if (e != GD.OK) value = Var.Nil;
            return e;
        }

        /// <summary>parse_tag_assign_eof with a simple tag (ConfigFile): either a "[section]" (tag set, assign "") or a
        /// "key = value" (assign set); ERR_FILE_EOF at the end.</summary>
        public int ParseTagAssignEof(ref int line, out string err, out string tag, out string assign, out Var value)
        {
            err = "";
            tag = null;
            assign = "";
            value = Var.Nil;
            var what = new StringBuilder();
            while (true)
            {
                char c;
                if (_saved != '\0') { c = _saved; _saved = '\0'; }
                else c = GetChar();
                if (IsEof) return GD.ERR_FILE_EOF;
                if (c == ';')
                {
                    while (true)
                    {
                        char ch = GetChar();
                        if (IsEof) return GD.ERR_FILE_EOF;
                        if (ch == '\n') { line++; break; }
                    }
                    continue;
                }
                if (c == '[' && what.Length == 0)
                {
                    // a simple tag: everything up to an unescaped ']'
                    var name = new StringBuilder();
                    bool escaping = false;
                    while (true)
                    {
                        char ch = GetChar();
                        if (IsEof) { err = "Unexpected EOF while parsing simple tag"; return GD.ERR_PARSE_ERROR; }
                        if (ch == ']')
                        {
                            if (escaping) escaping = false;
                            else break;
                        }
                        else if (ch == '\\') escaping = true;
                        else escaping = false;
                        name.Append(ch);
                    }
                    tag = name.ToString().StripEdges();
                    return GD.OK;
                }
                if (c > 32)
                {
                    if (c == '"')
                    {
                        _saved = '"';
                        int e = GetToken(out Token tk, ref line, out err);
                        if (e != GD.OK) return e;
                        if (tk.Type != Tk.String) { err = "Error reading quoted string"; return GD.ERR_INVALID_DATA; }
                        what.Clear();
                        what.Append(tk.Value.AsString());
                    }
                    else if (c != '=') what.Append(c);
                    else
                    {
                        assign = what.ToString();
                        GetToken(out Token tk, ref line, out err);
                        return ParseValue(tk, out value, ref line, out err);
                    }
                }
                else if (c == '\n') line++;
            }
        }
    }

    /// <summary>Godot's Marshalls singleton.</summary>
    public static class Marshalls
    {
        public static string VariantToBase64(Var v, bool fullObjects = false)
        {
            var b = GMarshal.VarToBytes(v, fullObjects);
            if (b.Length == 0) { GD.PushError("Error when trying to encode Variant."); return ""; }
            return GMarshal.B64Encode(b);
        }

        public static Var Base64ToVariant(string s, bool allowObjects = false)
        {
            if (!GMarshal.B64Decode(s, out byte[] b)) { GD.PushError("Condition \"CryptoCore::b64_decode(...) != OK\" is true. Returning: Variant()"); return Var.Nil; }
            int e = GMarshal.DecodeVariant(b, 0, b.Length, out Var v, out _, allowObjects);
            if (e != GD.OK) { GD.PushError("Error when trying to decode Variant."); return Var.Nil; }
            return v;
        }

        public static string RawToBase64(byte[] b)
        {
            string r = GMarshal.B64Encode(b);
            if (r.Length == 0) GD.PushError("Condition \"ret.is_empty()\" is true. Returning: ret");
            return r;
        }

        public static byte[] Base64ToRaw(string s)
        {
            if (!GMarshal.B64Decode(s, out byte[] b)) { GD.PushError("Condition \"CryptoCore::b64_decode(...) != OK\" is true. Returning: Vector<uint8_t>()"); return Array.Empty<byte>(); }
            return b;
        }

        public static string Utf8ToBase64(string s)
        {
            if (string.IsNullOrEmpty(s)) return "";
            return GMarshal.B64Encode(Encoding.UTF8.GetBytes(s));
        }

        public static string Base64ToUtf8(string s)
        {
            if (!GMarshal.B64Decode(s, out byte[] b)) { GD.PushError("Condition \"CryptoCore::b64_decode(...) != OK\" is true. Returning: String()"); return ""; }
            return GMarshal.Utf8(b, 0, b.Length, out _);
        }
    }

    public static partial class GD
    {
        /// <summary>var_to_bytes(v).</summary>
        public static byte[] VarToBytes(Var v) => GMarshal.VarToBytes(v);
        /// <summary>bytes_to_var(bytes).</summary>
        public static Var BytesToVar(byte[] b) => GMarshal.BytesToVar(b);
        public static byte[] VarToBytesWithObjects(Var v) => GMarshal.VarToBytes(v, true);
        public static Var BytesToVarWithObjects(byte[] b) => GMarshal.BytesToVar(b, true);
        /// <summary>var_to_str(v).</summary>
        public static string VarToStr(Var v) => GMarshal.VarToStr(v);
        /// <summary>str_to_var(text).</summary>
        public static Var StrToVar(string s) => GMarshal.StrToVar(s);
    }
}
