// The GDScript runtime the ported game code runs on (no engine references). Var is Godot's Variant: int and float
// kept apart (JSON numbers arrive as floats, int/int divides as integers), `==` across int and float, truthiness,
// str()'s exact text, hash(), and dictionary keys that are type-strict (1 and 1.0 are different keys) as in
// Godot 4. GDict / GArray (GContainers.cs) are Dictionary / Array, shared by reference like Godot's.
//
// Porting notes (PORTING_GUIDE.md has the full table):
//   d.a.b            -> d["a"]["b"]               (a missing key reads as Nil instead of erroring)
//   d.a.b = 1        -> d["a"].D["b"] = 1          (the last hop of a write must be the container itself: .D / .A)
//   x is int         -> x.IsInt ;  x == null -> x.IsNull ;  if x: -> if (x)
//   int(x) float(x) str(x) bool(x) -> (int)x (double)x GD.Str(x) (bool)x   (same rules as GDScript's constructors)
using System;
using System.Collections;
using System.Collections.Generic;

namespace Fatebound.Sim
{
    public enum VT : byte { Nil, Bool, Int, Float, String, Vec2, Vec2i, Vec3, Dict, Arr, Obj }

    /// <summary>A value type from another assembly stored in a Var (Color, Rect2, Transform...): its Godot type number,
    /// str() text, truthiness, hash() and arithmetic with other Vars.</summary>
    public interface IGodotValue
    {
        int GodotType { get; }
        string GodotStr();
        bool GodotIsZero { get; }
        uint GodotHash();
        /// <summary>op is one of + - * / ; self is the left operand when selfLeft. False: not supported.</summary>
        bool GodotOp(char op, Var other, bool selfLeft, out Var result);
    }

    /// <summary>An engine object that can be freed while references remain (Node): is_instance_valid() and `== null`
    /// see a freed one as gone.</summary>
    public interface IGodotObject
    {
        bool IsFreed { get; }
        ulong GetInstanceId();
        string GetClass();
    }

    public readonly struct Var : IEquatable<Var>, IEnumerable<Var>
    {
        public readonly VT Type;
        readonly long _n;          // bool / int / double bits / Vec2 floats / Vec2i ints
        readonly object _o;        // string, Vec3 (boxed), GDict, GArray, any other object

        Var(VT t, long n, object o) { Type = t; _n = n; _o = o; }

        public static readonly Var Nil = default;

        // ------------------------------------------------------------------ construction
        public static implicit operator Var(bool b) => new Var(VT.Bool, b ? 1 : 0, null);
        public static implicit operator Var(int i) => new Var(VT.Int, i, null);
        public static implicit operator Var(long i) => new Var(VT.Int, i, null);
        public static implicit operator Var(float f) => new Var(VT.Float, BitConverter.DoubleToInt64Bits(f), null);
        public static implicit operator Var(double d) => new Var(VT.Float, BitConverter.DoubleToInt64Bits(d), null);
        public static implicit operator Var(string s) => s == null ? Nil : new Var(VT.String, 0, s);
        public static implicit operator Var(Vec2 v) => new Var(VT.Vec2, Pack(v.x, v.y), null);
        public static implicit operator Var(Vec2i v) => new Var(VT.Vec2i, ((long)v.y << 32) | (uint)v.x, null);
        public static implicit operator Var(Vec3 v) => new Var(VT.Vec3, 0, v);
        public static implicit operator Var(GDict d) => d == null ? Nil : new Var(VT.Dict, 0, d);
        public static implicit operator Var(GArray a) => a == null ? Nil : new Var(VT.Arr, 0, a);
        public static implicit operator Var(Delegate f) => f == null ? Nil : new Var(VT.Obj, 0, f);

        /// <summary>Any C# value as a Var (numbers, strings, vectors, containers; anything else is held as an object).</summary>
        public static Var Of(object o)
        {
            switch (o)
            {
                case null: return Nil;
                case Var v: return v;
                case bool b: return b;
                case int i: return i;
                case long l: return l;
                case double d: return d;
                case float f: return f;
                case string s: return s;
                case Vec2 v2: return v2;
                case Vec2i v2i: return v2i;
                case Vec3 v3: return v3;
                case GDict gd: return gd;
                case GArray ga: return ga;
                case short sh: return (int)sh;
                case byte by: return (int)by;
                case sbyte sb: return (int)sb;
                case ushort us: return (int)us;
                case uint ui: return (long)ui;
                case ulong ul: return unchecked((long)ul);
                case char c: return c.ToString();
                default: return new Var(VT.Obj, 0, o);
            }
        }

        static long Pack(float x, float y) =>
            ((long)BitConverter.SingleToInt32Bits(y) << 32) | (uint)BitConverter.SingleToInt32Bits(x);

        // ------------------------------------------------------------------ type tests
        public bool IsNil => Type == VT.Nil;
        /// <summary>GDScript's `x == null`: Nil, or a freed object.</summary>
        public bool IsNull => Type == VT.Nil || (Type == VT.Obj && _o is IGodotObject g && g.IsFreed);
        public bool IsBool => Type == VT.Bool;
        public bool IsInt => Type == VT.Int;
        public bool IsFloat => Type == VT.Float;
        /// <summary>int or float (Godot's is_num()).</summary>
        public bool IsNum => Type == VT.Int || Type == VT.Float;
        public bool IsString => Type == VT.String;
        public bool IsVec2 => Type == VT.Vec2;
        public bool IsVec2i => Type == VT.Vec2i;
        public bool IsVec3 => Type == VT.Vec3;
        public bool IsDict => Type == VT.Dict;
        public bool IsArr => Type == VT.Arr;
        public bool IsObj => Type == VT.Obj;
        /// <summary>`x is T` (any held type, value types included).</summary>
        public bool Is<T>() => Obj is T;

        /// <summary>The value as a plain C# object (int as long, float as double, Vec2 boxed...).</summary>
        public object Obj
        {
            get
            {
                switch (Type)
                {
                    case VT.Nil: return null;
                    case VT.Bool: return _n != 0;
                    case VT.Int: return _n;
                    case VT.Float: return BitConverter.Int64BitsToDouble(_n);
                    case VT.Vec2: return Vec2Val;
                    case VT.Vec2i: return Vec2iVal;
                    default: return _o;
                }
            }
        }

        /// <summary>Godot's typeof() number (TYPE_INT == 2, TYPE_DICTIONARY == 27...).</summary>
        public int GodotType
        {
            get
            {
                switch (Type)
                {
                    case VT.Nil: return GD.TYPE_NIL;
                    case VT.Bool: return GD.TYPE_BOOL;
                    case VT.Int: return GD.TYPE_INT;
                    case VT.Float: return GD.TYPE_FLOAT;
                    case VT.String: return GD.TYPE_STRING;
                    case VT.Vec2: return GD.TYPE_VECTOR2;
                    case VT.Vec2i: return GD.TYPE_VECTOR2I;
                    case VT.Vec3: return GD.TYPE_VECTOR3;
                    case VT.Dict: return GD.TYPE_DICTIONARY;
                    case VT.Arr: return GD.TYPE_ARRAY;
                }
                switch (_o)
                {
                    case IGodotValue gv: return gv.GodotType;
                    case IGodotObject _: return GD.TYPE_OBJECT;
                    case Delegate _: return GD.TYPE_CALLABLE;
                    case byte[] _: return GD.TYPE_PACKED_BYTE_ARRAY;
                    case int[] _: case List<int> _: return GD.TYPE_PACKED_INT32_ARRAY;
                    case long[] _: case List<long> _: return GD.TYPE_PACKED_INT64_ARRAY;
                    case float[] _: case List<float> _: return GD.TYPE_PACKED_FLOAT32_ARRAY;
                    case double[] _: case List<double> _: return GD.TYPE_PACKED_FLOAT64_ARRAY;
                    case string[] _: case List<string> _: return GD.TYPE_PACKED_STRING_ARRAY;
                    case Vec2[] _: case List<Vec2> _: return GD.TYPE_PACKED_VECTOR2_ARRAY;
                    case Vec3[] _: case List<Vec3> _: return GD.TYPE_PACKED_VECTOR3_ARRAY;
                }
                return GD.TYPE_OBJECT;
            }
        }

        // ------------------------------------------------------------------ conversions out
        Vec2 Vec2Val => new Vec2(BitConverter.Int32BitsToSingle((int)_n), BitConverter.Int32BitsToSingle((int)(_n >> 32)));
        Vec2i Vec2iVal => new Vec2i((int)_n, (int)(_n >> 32));
        double FloatVal => BitConverter.Int64BitsToDouble(_n);

        /// <summary>bool(x): Godot's truthiness (0, 0.0, "", empty containers, zero vectors, null and freed objects are false).</summary>
        public bool Truthy
        {
            get
            {
                switch (Type)
                {
                    case VT.Nil: return false;
                    case VT.Bool:
                    case VT.Int: return _n != 0;
                    case VT.Float: return FloatVal != 0.0;
                    case VT.String: return ((string)_o).Length > 0;
                    case VT.Vec2: { var v = Vec2Val; return v.x != 0f || v.y != 0f; }
                    case VT.Vec2i: return _n != 0;
                    case VT.Vec3: { var v = (Vec3)_o; return v.x != 0f || v.y != 0f || v.z != 0f; }
                    case VT.Dict: return ((GDict)_o).Size() > 0;
                    case VT.Arr: return ((GArray)_o).Size() > 0;
                }
                switch (_o)
                {
                    case IGodotObject g: return !g.IsFreed;
                    case IGodotValue gv: return !gv.GodotIsZero;
                    case ICollection c: return c.Count > 0;
                }
                return true;
            }
        }

        /// <summary>int(x): float truncates toward zero, String parses as String.to_int(), bool is 0/1.</summary>
        public long AsLong()
        {
            switch (Type)
            {
                case VT.Bool:
                case VT.Int: return _n;
                case VT.Float: return DoubleToLong(FloatVal);
                case VT.String: return GStr.ToInt((string)_o);
                default: return 0;
            }
        }

        internal static long DoubleToLong(double d)
        {
            // (C++'s (int64_t) cast of an out-of-range or NaN double: x86-64 gives INT64_MIN)
            if (double.IsNaN(d) || d >= 9.2233720368547758e18 || d < -9.2233720368547758e18) return long.MinValue;
            return (long)d;
        }

        public int AsInt() => unchecked((int)AsLong());

        /// <summary>float(x): int widens, String parses as String.to_float(), bool is 0.0/1.0.</summary>
        public double AsFloat()
        {
            switch (Type)
            {
                case VT.Bool:
                case VT.Int: return _n;
                case VT.Float: return FloatVal;
                case VT.String: return GStr.ToFloat((string)_o);
                default: return 0.0;
            }
        }

        /// <summary>The string if this is one; str(x) otherwise ("" for Nil).</summary>
        public string AsString() => Type == VT.String ? (string)_o : Type == VT.Nil ? "" : GFormat.Str(this);

        public Vec2 AsVec2()
        {
            switch (Type)
            {
                case VT.Vec2: return Vec2Val;
                case VT.Vec2i: { var v = Vec2iVal; return new Vec2(v.x, v.y); }
                default: return Vec2.Zero;
            }
        }

        public Vec2i AsVec2i()
        {
            switch (Type)
            {
                case VT.Vec2i: return Vec2iVal;
                case VT.Vec2: { var v = Vec2Val; return new Vec2i((int)v.x, (int)v.y); }
                default: return new Vec2i(0, 0);
            }
        }

        public Vec3 AsVec3() => Type == VT.Vec3 ? (Vec3)_o : Vec3.Zero;
        public GDict AsDict() => _o as GDict;
        public GArray AsArr() => _o as GArray;
        /// <summary>The held object as T (default when it isn't one).</summary>
        public T As<T>() => Obj is T t ? t : default;

        // short forms for chains: d["a"].D["b"] = 1 ; d["list"].A.Append(x)
        public GDict D => _o as GDict;
        public GArray A => _o as GArray;
        public string S => AsString();
        public int I => AsInt();
        public long L => AsLong();
        public double F => AsFloat();
        public bool B => Truthy;
        public Vec2 V2 => AsVec2();
        public Vec3 V3 => AsVec3();

        public static explicit operator bool(Var v) => v.Truthy;
        public static explicit operator int(Var v) => v.AsInt();
        public static explicit operator long(Var v) => v.AsLong();
        public static explicit operator double(Var v) => v.AsFloat();
        public static explicit operator float(Var v) => (float)v.AsFloat();
        public static explicit operator string(Var v) => v.AsString();
        public static explicit operator Vec2(Var v) => v.AsVec2();
        public static explicit operator Vec2i(Var v) => v.AsVec2i();
        public static explicit operator Vec3(Var v) => v.AsVec3();
        public static explicit operator GDict(Var v) => v._o as GDict;
        public static explicit operator GArray(Var v) => v._o as GArray;

        public static bool operator true(Var v) => v.Truthy;
        public static bool operator false(Var v) => !v.Truthy;
        public static bool operator !(Var v) => !v.Truthy;
        /// <summary>(`a and b` / `a or b` in GDScript give bools: these keep C#'s && / || usable on Vars.)</summary>
        public static Var operator &(Var a, Var b) => a.Truthy && b.Truthy;
        public static Var operator |(Var a, Var b) => a.Truthy || b.Truthy;

        // ------------------------------------------------------------------ arithmetic (Variant::evaluate)
        public static Var operator +(Var a, Var b) => Arith('+', a, b);
        public static Var operator -(Var a, Var b) => Arith('-', a, b);
        public static Var operator *(Var a, Var b) => Arith('*', a, b);
        public static Var operator /(Var a, Var b) => Arith('/', a, b);
        public static Var operator %(Var a, Var b) => Arith('%', a, b);

        public static Var operator -(Var a)
        {
            switch (a.Type)
            {
                case VT.Int: return unchecked(-a._n);
                case VT.Float: return -a.FloatVal;
                case VT.Vec2: return -a.Vec2Val;
                case VT.Vec2i: { var v = a.Vec2iVal; return new Vec2i(-v.x, -v.y); }
                case VT.Vec3: { var v = (Vec3)a._o; return new Vec3(-v.x, -v.y, -v.z); }
            }
            if (a._o is IGodotValue gv && gv.GodotOp('n', Nil, true, out var r)) return r;
            return Bad("-", a, Nil);
        }

        public static Var operator +(Var a) => a;

        static Var Bad(string op, Var a, Var b)
        {
            GD.PushError("Invalid operands '" + GD.TypeString(a.GodotType) + "' and '" + GD.TypeString(b.GodotType) + "' in operator '" + op + "'.");
            return Nil;
        }

        static Var Arith(char op, Var a, Var b)
        {
            VT ta = a.Type, tb = b.Type;
            if (ta == VT.Int && tb == VT.Int)
            {
                long x = a._n, y = b._n;
                switch (op)
                {
                    case '+': return unchecked(x + y);
                    case '-': return unchecked(x - y);
                    case '*': return unchecked(x * y);
                    case '/':
                        if (y == 0) { GD.PushError("Division by zero error in operator '/'."); return 0; }
                        if (x == long.MinValue && y == -1) return long.MinValue;
                        return x / y;
                    case '%':
                        if (y == 0) { GD.PushError("Modulo by zero error in operator '%'."); return 0; }
                        if (y == -1) return 0;
                        return x % y;
                }
            }
            if ((ta == VT.Int || ta == VT.Float) && (tb == VT.Int || tb == VT.Float))
            {
                double x = a.AsFloat(), y = b.AsFloat();
                switch (op)
                {
                    case '+': return x + y;
                    case '-': return x - y;
                    case '*': return x * y;
                    case '/': return x / y;
                    case '%': return x % y;     // (fmod; Godot itself refuses floats here)
                }
            }
            if (ta == VT.String)
            {
                if (op == '%') return GFormat.SprintfOp((string)a._o, b);
                if (op == '+' && tb == VT.String) return string.Concat((string)a._o, (string)b._o);
                if (op == '+') return string.Concat((string)a._o, GFormat.Str(b));
                return Bad(op.ToString(), a, b);
            }
            if (op == '+' && tb == VT.String && ta != VT.Obj) return string.Concat(GFormat.Str(a), (string)b._o);
            // (a vector with a Basis / Transform / Quaternion / Projection...: those types implement the operator)
            if ((ta == VT.Obj && a._o is IGodotValue gva && gva.GodotOp(op, b, true, out var rv))
                || (tb == VT.Obj && b._o is IGodotValue gvb && gvb.GodotOp(op, a, false, out rv))) return rv;
            if (ta == VT.Vec2 || tb == VT.Vec2) return Vec2Arith(op, a, b);
            if (ta == VT.Vec2i || tb == VT.Vec2i) return Vec2iArith(op, a, b);
            if (ta == VT.Vec3 || tb == VT.Vec3) return Vec3Arith(op, a, b);
            if (ta == VT.Arr && tb == VT.Arr && op == '+')
            {
                var r = ((GArray)a._o).Duplicate();
                r.AppendArray((GArray)b._o);
                return r;
            }
            if (a._o is IGodotValue ga && ga.GodotOp(op, b, true, out var res)) return res;
            if (b._o is IGodotValue gb && gb.GodotOp(op, a, false, out res)) return res;
            return Bad(op.ToString(), a, b);
        }

        static Var Vec2Arith(char op, Var a, Var b)
        {
            if (a.Type == VT.Vec2 && b.Type == VT.Vec2)
            {
                Vec2 x = a.Vec2Val, y = b.Vec2Val;
                switch (op)
                {
                    case '+': return x + y;
                    case '-': return x - y;
                    case '*': return x * y;
                    case '/': return x / y;
                }
            }
            else if (a.Type == VT.Vec2 && b.IsNum)
            {
                Vec2 x = a.Vec2Val; double s = b.AsFloat();
                if (op == '*') return x * s;
                if (op == '/') return x / s;
            }
            else if (b.Type == VT.Vec2 && a.IsNum)
            {
                if (op == '*') return a.AsFloat() * b.Vec2Val;
            }
            else if (a.Type == VT.Vec2 && b.Type == VT.Vec2i) return Vec2Arith(op, a, b.AsVec2());
            else if (a.Type == VT.Vec2i && b.Type == VT.Vec2) return Vec2Arith(op, a.AsVec2(), b);
            return Bad(op.ToString(), a, b);
        }

        static Var Vec2iArith(char op, Var a, Var b)
        {
            if (a.Type == VT.Vec2i && b.Type == VT.Vec2i)
            {
                Vec2i x = a.Vec2iVal, y = b.Vec2iVal;
                switch (op)
                {
                    case '+': return new Vec2i(x.x + y.x, x.y + y.y);
                    case '-': return new Vec2i(x.x - y.x, x.y - y.y);
                    case '*': return new Vec2i(x.x * y.x, x.y * y.y);
                    case '/': return new Vec2i(y.x == 0 ? 0 : x.x / y.x, y.y == 0 ? 0 : x.y / y.y);
                    case '%': return new Vec2i(y.x == 0 ? 0 : x.x % y.x, y.y == 0 ? 0 : x.y % y.y);
                }
            }
            else if (a.Type == VT.Vec2i && b.IsInt)
            {
                Vec2i x = a.Vec2iVal; int s = (int)b._n;
                if (op == '*') return new Vec2i(x.x * s, x.y * s);
                if (op == '/') return s == 0 ? Bad("/", a, b) : new Vec2i(x.x / s, x.y / s);
                if (op == '%') return s == 0 ? Bad("%", a, b) : new Vec2i(x.x % s, x.y % s);
            }
            else if (a.Type == VT.Vec2i && b.IsFloat)
            {
                // Vector2i * float -> Vector2
                if (op == '*') return a.AsVec2() * b.FloatVal;
                if (op == '/') return a.AsVec2() / b.FloatVal;
            }
            else if (b.Type == VT.Vec2i && a.IsInt && op == '*') { var y = b.Vec2iVal; int s = (int)a._n; return new Vec2i(y.x * s, y.y * s); }
            else if (b.Type == VT.Vec2i && a.IsFloat && op == '*') return a.FloatVal * b.AsVec2();
            return Bad(op.ToString(), a, b);
        }

        static Var Vec3Arith(char op, Var a, Var b)
        {
            if (a.Type == VT.Vec3 && b.Type == VT.Vec3)
            {
                Vec3 x = (Vec3)a._o, y = (Vec3)b._o;
                switch (op)
                {
                    case '+': return x + y;
                    case '-': return x - y;
                    case '*': return new Vec3(x.x * y.x, x.y * y.y, x.z * y.z);
                    case '/': return new Vec3(x.x / y.x, x.y / y.y, x.z / y.z);
                }
            }
            else if (a.Type == VT.Vec3 && b.IsNum)
            {
                Vec3 x = (Vec3)a._o; float s = (float)b.AsFloat();
                if (op == '*') return new Vec3(x.x * s, x.y * s, x.z * s);
                if (op == '/') return new Vec3(x.x / s, x.y / s, x.z / s);
            }
            else if (b.Type == VT.Vec3 && a.IsNum && op == '*')
            {
                Vec3 y = (Vec3)b._o; float s = (float)a.AsFloat();
                return new Vec3(y.x * s, y.y * s, y.z * s);
            }
            return Bad(op.ToString(), a, b);
        }

        // ------------------------------------------------------------------ comparison (OP_EQUAL / OP_LESS ...)
        public static bool operator ==(Var a, Var b) => Equal(a, b);
        public static bool operator !=(Var a, Var b) => !Equal(a, b);
        public static bool operator <(Var a, Var b) => Less(a, b);
        public static bool operator >(Var a, Var b) => Less(b, a);
        public static bool operator <=(Var a, Var b) => !Less(b, a) && Comparable(a, b);
        public static bool operator >=(Var a, Var b) => !Less(a, b) && Comparable(a, b);

        static bool Comparable(Var a, Var b)
        {
            if (a.IsNum && b.IsNum) return !(double.IsNaN(a.AsFloat()) || double.IsNaN(b.AsFloat()));
            return a.Type == b.Type && (a.Type == VT.String || a.Type == VT.Bool || a.Type == VT.Vec2 || a.Type == VT.Vec2i
                || a.Type == VT.Vec3 || a.Type == VT.Arr);
        }

        /// <summary>GDScript's `==`: 1 == 1.0, deep for dictionaries/arrays, false across unrelated types.</summary>
        public static bool Equal(Var a, Var b)
        {
            if (a.Type == VT.Nil) return b.IsNull;
            if (b.Type == VT.Nil) return a.IsNull;
            switch (a.Type)
            {
                case VT.Bool: return b.Type == VT.Bool && a._n == b._n;
                case VT.Int:
                    if (b.Type == VT.Int) return a._n == b._n;
                    if (b.Type == VT.Float) return a._n == b.FloatVal;
                    return false;
                case VT.Float:
                    if (b.Type == VT.Float) return a.FloatVal == b.FloatVal;
                    if (b.Type == VT.Int) return a.FloatVal == b._n;
                    return false;
                case VT.String: return b.Type == VT.String && string.Equals((string)a._o, (string)b._o);
                case VT.Vec2: return b.Type == VT.Vec2 && a.Vec2Val == b.Vec2Val;
                case VT.Vec2i: return b.Type == VT.Vec2i && a._n == b._n;
                case VT.Vec3: return b.Type == VT.Vec3 && (Vec3)a._o == (Vec3)b._o;
                case VT.Dict: return b.Type == VT.Dict && GDict.RecursiveEqual((GDict)a._o, (GDict)b._o, 0);
                case VT.Arr: return b.Type == VT.Arr && GArray.RecursiveEqual((GArray)a._o, (GArray)b._o, 0);
            }
            if (b.Type != VT.Obj) return false;
            return ReferenceEquals(a._o, b._o) || a._o.Equals(b._o);
        }

        /// <summary>GDScript's `<` (false across unrelated types, as Array.sort's comparator).</summary>
        public static bool Less(Var a, Var b)
        {
            if (a.IsNum && b.IsNum)
            {
                if (a.Type == VT.Int && b.Type == VT.Int) return a._n < b._n;
                return a.AsFloat() < b.AsFloat();
            }
            if (a.Type != b.Type) return false;
            switch (a.Type)
            {
                case VT.Bool: return a._n < b._n;
                case VT.String: return GStr.Less((string)a._o, (string)b._o);
                case VT.Vec2:
                    {
                        Vec2 x = a.Vec2Val, y = b.Vec2Val;
                        return x.x == y.x ? x.y < y.y : x.x < y.x;
                    }
                case VT.Vec2i:
                    {
                        Vec2i x = a.Vec2iVal, y = b.Vec2iVal;
                        return x.x == y.x ? x.y < y.y : x.x < y.x;
                    }
                case VT.Vec3:
                    {
                        Vec3 x = (Vec3)a._o, y = (Vec3)b._o;
                        if (x.x == y.x) return x.y == y.y ? x.z < y.z : x.y < y.y;
                        return x.x < y.x;
                    }
                case VT.Arr: return GArray.LessThan((GArray)a._o, (GArray)b._o);
            }
            return false;
        }

        // ------------------------------------------------------------------ key equality (Variant::hash_compare)
        /// <summary>Dictionary-key equality: same type and value (1 != 1.0 here), NaN equal to NaN, containers by content.</summary>
        public bool Equals(Var o) => HashCompare(this, o, 0);
        public override bool Equals(object obj) => obj is Var v && HashCompare(this, v, 0);

        internal static bool HashCompare(Var a, Var b, int depth)
        {
            if (a.Type != b.Type) return false;
            switch (a.Type)
            {
                case VT.Nil: return true;
                case VT.Bool:
                case VT.Int:
                case VT.Vec2i: return a._n == b._n;
                case VT.Float: { double x = a.FloatVal, y = b.FloatVal; return x == y || (double.IsNaN(x) && double.IsNaN(y)); }
                case VT.String: return string.Equals((string)a._o, (string)b._o);
                case VT.Vec2: { Vec2 x = a.Vec2Val, y = b.Vec2Val; return Feq(x.x, y.x) && Feq(x.y, y.y); }
                case VT.Vec3: { Vec3 x = (Vec3)a._o, y = (Vec3)b._o; return Feq(x.x, y.x) && Feq(x.y, y.y) && Feq(x.z, y.z); }
                case VT.Dict: return GDict.RecursiveHashCompare((GDict)a._o, (GDict)b._o, depth + 1);
                case VT.Arr: return GArray.RecursiveHashCompare((GArray)a._o, (GArray)b._o, depth + 1);
            }
            return ReferenceEquals(a._o, b._o) || (a._o != null && a._o.Equals(b._o));
        }

        static bool Feq(float x, float y) => x == y || (float.IsNaN(x) && float.IsNaN(y));

        public override int GetHashCode()
        {
            switch (Type)
            {
                case VT.Nil: return 0;
                case VT.Bool:
                case VT.Int:
                case VT.Vec2i: return _n.GetHashCode();
                case VT.Float:
                    {
                        double d = FloatVal;
                        if (d == 0.0) return 0;
                        if (double.IsNaN(d)) return 0x7ff80000;
                        return d.GetHashCode();
                    }
                case VT.String: return ((string)_o).GetHashCode();
                case VT.Obj: return _o.GetHashCode();
            }
            return unchecked((int)GodotHash(0));
        }

        /// <summary>Godot's Variant::hash() (GDScript's hash()): the engine's exact numbers.</summary>
        public uint GodotHash(int depth = 0)
        {
            switch (Type)
            {
                case VT.Nil: return 0;
                case VT.Bool: return _n != 0 ? 1u : 0u;
                case VT.Int: return GHashing.OneUint64(unchecked((ulong)_n));
                case VT.Float: return GHashing.Murmur3OneDouble(FloatVal);
                case VT.String: return GHash.Str((string)_o);
                case VT.Vec2:
                    {
                        var v = Vec2Val;
                        uint h = GHashing.Murmur3OneFloat(v.x);
                        h = GHashing.Murmur3OneFloat(v.y, h);
                        return GHashing.Fmix32(h);
                    }
                case VT.Vec2i:
                    {
                        var v = Vec2iVal;
                        uint h = GHashing.Murmur3One32((uint)v.x);
                        h = GHashing.Murmur3One32((uint)v.y, h);
                        return GHashing.Fmix32(h);
                    }
                case VT.Vec3:
                    {
                        var v = (Vec3)_o;
                        uint h = GHashing.Murmur3OneFloat(v.x);
                        h = GHashing.Murmur3OneFloat(v.y, h);
                        h = GHashing.Murmur3OneFloat(v.z, h);
                        return GHashing.Fmix32(h);
                    }
                case VT.Dict: return ((GDict)_o).RecursiveHash(depth);
                case VT.Arr: return ((GArray)_o).RecursiveHash(depth);
            }
            switch (_o)
            {
                case IGodotValue gv: return gv.GodotHash();
                case IGodotObject go: return GHashing.OneUint64(go.GetInstanceId());
                case IList list:
                    {
                        uint h = GHashing.Murmur3One32((uint)GD.TYPE_ARRAY);
                        foreach (var x in list) h = GHashing.Murmur3One32(Of(x).GodotHash(depth + 1), h);
                        return GHashing.Fmix32(h);
                    }
            }
            return unchecked((uint)_o.GetHashCode());
        }

        // ------------------------------------------------------------------ container access
        /// <summary>Hooks for property access on held objects (`node.text` through an untyped Var): filled by the
        /// GUI assembly (reflection by GDScript name).</summary>
        public static Func<object, string, Var> ObjGet;
        public static Action<object, string, Var> ObjSet;

        public Var this[string key]
        {
            get
            {
                switch (Type)
                {
                    case VT.Dict: return ((GDict)_o)[key];
                    case VT.Vec2:
                        if (key == "x") return Vec2Val.x;
                        if (key == "y") return Vec2Val.y;
                        break;
                    case VT.Vec2i:
                        if (key == "x") return Vec2iVal.x;
                        if (key == "y") return Vec2iVal.y;
                        break;
                    case VT.Vec3:
                        {
                            var v = (Vec3)_o;
                            if (key == "x") return v.x;
                            if (key == "y") return v.y;
                            if (key == "z") return v.z;
                            break;
                        }
                    case VT.Obj:
                        if (ObjGet != null) return ObjGet(_o, key);
                        break;
                }
                return Index(key);
            }
            set
            {
                if (Type == VT.Dict) ((GDict)_o)[key] = value;
                else if (Type == VT.Obj && ObjSet != null) ObjSet(_o, key, value);
                else SetIndex(key, value);
            }
        }

        public Var this[int i]
        {
            get
            {
                switch (Type)
                {
                    case VT.Arr: return ((GArray)_o)[i];
                    case VT.Dict: return ((GDict)_o)[i];
                }
                return Index(i);
            }
            set
            {
                if (Type == VT.Arr) ((GArray)_o)[i] = value;
                else if (Type == VT.Dict) ((GDict)_o)[i] = value;
                else SetIndex(i, value);
            }
        }

        public Var this[Var key]
        {
            get
            {
                if (Type == VT.Dict) return ((GDict)_o)[key];
                if (Type == VT.Arr && key.IsNum) return ((GArray)_o)[(int)key.AsLong()];
                if (key.Type == VT.String) return this[(string)key._o];
                return Index(key);
            }
            set
            {
                if (Type == VT.Dict) ((GDict)_o)[key] = value;
                else if (Type == VT.Arr && key.IsNum) ((GArray)_o)[(int)key.AsLong()] = value;
                else if (key.Type == VT.String) this[(string)key._o] = value;
                else SetIndex(key, value);
            }
        }

        Var Index(Var key)
        {
            switch (Type)
            {
                case VT.String:
                    if (key.IsInt)
                    {
                        var s = (string)_o;
                        int i = (int)key._n;
                        if (i < 0) i += s.Length;
                        if (i >= 0 && i < s.Length) return s.Substring(i, 1);
                    }
                    break;
                case VT.Vec2:
                    if (key.IsInt) return key._n == 0 ? Vec2Val.x : Vec2Val.y;
                    break;
                case VT.Vec2i:
                    if (key.IsInt) return key._n == 0 ? Vec2iVal.x : Vec2iVal.y;
                    break;
                case VT.Vec3:
                    if (key.IsInt) { var v = (Vec3)_o; return key._n == 0 ? v.x : key._n == 1 ? v.y : v.z; }
                    break;
                case VT.Obj:
                    if (_o is IList list && key.IsInt)
                    {
                        int i = (int)key._n;
                        if (i < 0) i += list.Count;
                        if (i >= 0 && i < list.Count) return Of(list[i]);
                    }
                    else if (key.Type == VT.String && ObjGet != null) return ObjGet(_o, (string)key._o);
                    break;
            }
            if (Type != VT.Nil) GD.PushError("Invalid access to index/key " + GFormat.Clean(key) + " on a value of type '" + GD.TypeString(GodotType) + "'.");
            return Nil;
        }

        void SetIndex(Var key, Var value)
        {
            if (Type == VT.Obj && _o is IList list && key.IsInt)
            {
                int i = (int)key._n;
                if (i < 0) i += list.Count;
                if (i >= 0 && i < list.Count) { list[i] = ConvertTo(value, list.GetType()); return; }
            }
            GD.PushError("Invalid assignment of index/key " + GFormat.Clean(key) + " on a value of type '" + GD.TypeString(GodotType) + "'.");
        }

        static object ConvertTo(Var v, Type listType)
        {
            var el = listType.IsArray ? listType.GetElementType() : (listType.IsGenericType ? listType.GetGenericArguments()[0] : typeof(object));
            if (el == typeof(int)) return v.AsInt();
            if (el == typeof(long)) return v.AsLong();
            if (el == typeof(float)) return (float)v.AsFloat();
            if (el == typeof(double)) return v.AsFloat();
            if (el == typeof(string)) return v.AsString();
            if (el == typeof(byte)) return (byte)v.AsLong();
            if (el == typeof(bool)) return v.Truthy;
            if (el == typeof(Var)) return v;
            return v.Obj;
        }

        /// <summary>size() / length(): dictionary, array, string, packed array.</summary>
        public int Size()
        {
            switch (Type)
            {
                case VT.Dict: return ((GDict)_o).Size();
                case VT.Arr: return ((GArray)_o).Size();
                case VT.String: return ((string)_o).Length;
                case VT.Obj: if (_o is ICollection c) return c.Count; break;
            }
            return 0;
        }

        public bool IsEmpty() => Size() == 0;

        /// <summary>has(): a dictionary key, an array element, a substring.</summary>
        public bool Has(Var x)
        {
            switch (Type)
            {
                case VT.Dict: return ((GDict)_o).Has(x);
                case VT.Arr: return ((GArray)_o).Has(x);
                case VT.String: return x.Type == VT.String && ((string)_o).Contains((string)x._o);
                case VT.Obj:
                    if (_o is IList list) { foreach (var e in list) if (HashCompare(Of(e), x, 0)) return true; }
                    break;
            }
            return false;
        }

        /// <summary>`x in container`.</summary>
        public bool Contains(Var x) => Has(x);

        public Var Get(Var key, Var dflt = default)
        {
            if (Type == VT.Dict) return ((GDict)_o).Get(key, dflt);
            if (Type == VT.Arr) return key.IsNum ? ((GArray)_o).Get((int)key.AsLong(), dflt) : dflt;
            if (Type == VT.Obj && key.Type == VT.String && ObjGet != null) return ObjGet(_o, (string)key._o);
            return dflt;
        }

        public GArray Keys() => Type == VT.Dict ? ((GDict)_o).Keys() : new GArray();
        public GArray Values() => Type == VT.Dict ? ((GDict)_o).Values() : new GArray();

        public void Append(Var x)
        {
            if (Type == VT.Arr) ((GArray)_o).Append(x);
            else if (Type == VT.Obj && _o is IList list) list.Add(ConvertTo(x, list.GetType()));
            else GD.PushError("append() on a value of type '" + GD.TypeString(GodotType) + "'.");
        }

        public bool Erase(Var x)
        {
            if (Type == VT.Dict) return ((GDict)_o).Erase(x);
            if (Type == VT.Arr) { ((GArray)_o).Erase(x); return true; }
            return false;
        }

        public void Clear()
        {
            if (Type == VT.Dict) ((GDict)_o).Clear();
            else if (Type == VT.Arr) ((GArray)_o).Clear();
            else if (_o is IList list) list.Clear();
        }

        public int Find(Var x, int from = 0)
        {
            if (Type == VT.Arr) return ((GArray)_o).Find(x, from);
            if (Type == VT.String && x.Type == VT.String) return GStr.Find((string)_o, (string)x._o, from);
            return -1;
        }

        /// <summary>duplicate(deep): dictionaries and arrays copied (nested ones too when deep); other values as they are.</summary>
        public Var Duplicate(bool deep = false)
        {
            if (Type == VT.Dict) return ((GDict)_o).Duplicate(deep);
            if (Type == VT.Arr) return ((GArray)_o).Duplicate(deep);
            return this;
        }

        // ------------------------------------------------------------------ iteration: `for x in v`
        public IEnumerator<Var> GetEnumerator()
        {
            switch (Type)
            {
                case VT.Dict:
                    foreach (var k in (GDict)_o) yield return k;
                    break;
                case VT.Arr:
                    {
                        var a = (GArray)_o;
                        for (int i = 0; i < a.Size(); i++) yield return a[i];
                        break;
                    }
                case VT.String:
                    {
                        var s = (string)_o;
                        for (int i = 0; i < s.Length; i++)
                        {
                            if (char.IsHighSurrogate(s[i]) && i + 1 < s.Length) { yield return s.Substring(i, 2); i++; }
                            else yield return s.Substring(i, 1);
                        }
                        break;
                    }
                case VT.Int:
                    for (long i = 0; i < _n; i++) yield return i;
                    break;
                case VT.Float:
                    for (long i = 0; i < FloatVal; i++) yield return i;
                    break;
                case VT.Obj:
                    if (_o is IEnumerable e) foreach (var x in e) yield return Of(x);
                    break;
            }
        }

        IEnumerator IEnumerable.GetEnumerator() => GetEnumerator();

        /// <summary>str(x).</summary>
        public override string ToString() => GFormat.Str(this);
    }

    /// <summary>Godot's hash functions (core/templates/hashfuncs.h).</summary>
    public static class GHashing
    {
        public const uint MURMUR3_SEED = 0x7F07C65;

        public static uint OneUint64(ulong v)
        {
            unchecked
            {
                v = (~v) + (v << 18);
                v = v ^ (v >> 31);
                v = v * 21;
                v = v ^ (v >> 11);
                v = v + (v << 6);
                v = v ^ (v >> 22);
                return (uint)v;
            }
        }

        public static uint Murmur3One32(uint p, uint seed = MURMUR3_SEED)
        {
            unchecked
            {
                p *= 0xcc9e2d51;
                p = (p << 15) | (p >> 17);
                p *= 0x1b873593;
                seed ^= p;
                seed = (seed << 13) | (seed >> 19);
                seed = seed * 5 + 0xe6546b64;
                return seed;
            }
        }

        public static uint Murmur3One64(ulong p, uint seed = MURMUR3_SEED)
        {
            seed = Murmur3One32((uint)(p & 0xFFFFFFFF), seed);
            return Murmur3One32((uint)(p >> 32), seed);
        }

        public static uint Murmur3OneFloat(float f, uint seed = MURMUR3_SEED)
        {
            if (f == 0f) f = 0f;
            else if (float.IsNaN(f)) f = float.NaN;
            int bits = BitConverter.SingleToInt32Bits(f);
            if (float.IsNaN(f)) bits = 0x7fc00000;
            return Murmur3One32(unchecked((uint)bits), seed);
        }

        public static uint Murmur3OneDouble(double d, uint seed = MURMUR3_SEED)
        {
            long bits;
            if (d == 0.0) bits = 0;
            else if (double.IsNaN(d)) bits = 0x7ff8000000000000;
            else bits = BitConverter.DoubleToInt64Bits(d);
            return Murmur3One64(unchecked((ulong)bits), seed);
        }

        public static uint Fmix32(uint h)
        {
            unchecked
            {
                h ^= h >> 16;
                h *= 0x85ebca6b;
                h ^= h >> 13;
                h *= 0xc2b2ae35;
                h ^= h >> 16;
                return h;
            }
        }
    }
}
