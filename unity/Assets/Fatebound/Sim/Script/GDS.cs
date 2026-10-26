// GDScript's global scope for the ported game code: str()/int()/float()/bool()/len()/typeof(), the TYPE_* and
// error constants, print / push_error, the global random generator (randf, randi_range, shuffle...), and the
// @GlobalScope math the sim's GD (GMath.cs) didn't need yet. Same names as GDScript, PascalCased.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Text;

namespace Fatebound.Sim
{
    public static partial class GD
    {
        // ------------------------------------------------------------------ Variant.Type
        public const int TYPE_NIL = 0, TYPE_BOOL = 1, TYPE_INT = 2, TYPE_FLOAT = 3, TYPE_STRING = 4, TYPE_VECTOR2 = 5,
            TYPE_VECTOR2I = 6, TYPE_RECT2 = 7, TYPE_RECT2I = 8, TYPE_VECTOR3 = 9, TYPE_VECTOR3I = 10, TYPE_TRANSFORM2D = 11,
            TYPE_VECTOR4 = 12, TYPE_VECTOR4I = 13, TYPE_PLANE = 14, TYPE_QUATERNION = 15, TYPE_AABB = 16, TYPE_BASIS = 17,
            TYPE_TRANSFORM3D = 18, TYPE_PROJECTION = 19, TYPE_COLOR = 20, TYPE_STRING_NAME = 21, TYPE_NODE_PATH = 22,
            TYPE_RID = 23, TYPE_OBJECT = 24, TYPE_CALLABLE = 25, TYPE_SIGNAL = 26, TYPE_DICTIONARY = 27, TYPE_ARRAY = 28,
            TYPE_PACKED_BYTE_ARRAY = 29, TYPE_PACKED_INT32_ARRAY = 30, TYPE_PACKED_INT64_ARRAY = 31,
            TYPE_PACKED_FLOAT32_ARRAY = 32, TYPE_PACKED_FLOAT64_ARRAY = 33, TYPE_PACKED_STRING_ARRAY = 34,
            TYPE_PACKED_VECTOR2_ARRAY = 35, TYPE_PACKED_VECTOR3_ARRAY = 36, TYPE_PACKED_COLOR_ARRAY = 37,
            TYPE_PACKED_VECTOR4_ARRAY = 38, TYPE_MAX = 39;

        static readonly string[] TypeNames = {
            "Nil", "bool", "int", "float", "String", "Vector2", "Vector2i", "Rect2", "Rect2i", "Vector3", "Vector3i",
            "Transform2D", "Vector4", "Vector4i", "Plane", "Quaternion", "AABB", "Basis", "Transform3D", "Projection",
            "Color", "StringName", "NodePath", "RID", "Object", "Callable", "Signal", "Dictionary", "Array",
            "PackedByteArray", "PackedInt32Array", "PackedInt64Array", "PackedFloat32Array", "PackedFloat64Array",
            "PackedStringArray", "PackedVector2Array", "PackedVector3Array", "PackedColorArray", "PackedVector4Array" };

        /// <summary>type_string(type).</summary>
        public static string TypeString(int t) => t >= 0 && t < TypeNames.Length ? TypeNames[t] : "<invalid type>";

        // ------------------------------------------------------------------ Error
        public const int OK = 0, FAILED = 1, ERR_UNAVAILABLE = 2, ERR_UNCONFIGURED = 3, ERR_UNAUTHORIZED = 4,
            ERR_PARAMETER_RANGE_ERROR = 5, ERR_OUT_OF_MEMORY = 6, ERR_FILE_NOT_FOUND = 7, ERR_FILE_BAD_DRIVE = 8,
            ERR_FILE_BAD_PATH = 9, ERR_FILE_NO_PERMISSION = 10, ERR_FILE_ALREADY_IN_USE = 11, ERR_FILE_CANT_OPEN = 12,
            ERR_FILE_CANT_WRITE = 13, ERR_FILE_CANT_READ = 14, ERR_FILE_UNRECOGNIZED = 15, ERR_FILE_CORRUPT = 16,
            ERR_FILE_MISSING_DEPENDENCIES = 17, ERR_FILE_EOF = 18, ERR_CANT_OPEN = 19, ERR_CANT_CREATE = 20,
            ERR_QUERY_FAILED = 21, ERR_ALREADY_IN_USE = 22, ERR_LOCKED = 23, ERR_TIMEOUT = 24, ERR_CANT_CONNECT = 25,
            ERR_CANT_RESOLVE = 26, ERR_CONNECTION_ERROR = 27, ERR_CANT_ACQUIRE_RESOURCE = 28, ERR_CANT_FORK = 29,
            ERR_INVALID_DATA = 30, ERR_INVALID_PARAMETER = 31, ERR_ALREADY_EXISTS = 32, ERR_DOES_NOT_EXIST = 33,
            ERR_DATABASE_CANT_READ = 34, ERR_DATABASE_CANT_WRITE = 35, ERR_COMPILATION_FAILED = 36,
            ERR_METHOD_NOT_FOUND = 37, ERR_LINK_FAILED = 38, ERR_SCRIPT_FAILED = 39, ERR_CYCLIC_LINK = 40,
            ERR_INVALID_DECLARATION = 41, ERR_DUPLICATE_SYMBOL = 42, ERR_PARSE_ERROR = 43, ERR_BUSY = 44, ERR_SKIP = 45,
            ERR_HELP = 46, ERR_BUG = 47, ERR_PRINTER_ON_FIRE = 48;

        public static string ErrorString(int e)
        {
            switch (e)
            {
                case OK: return "OK";
                case FAILED: return "Failed";
                case ERR_UNAVAILABLE: return "Unavailable";
                case ERR_FILE_NOT_FOUND: return "File not found";
                case ERR_FILE_CANT_OPEN: return "Can't open file";
                case ERR_CANT_CONNECT: return "Can't connect";
                case ERR_TIMEOUT: return "Timeout";
                case ERR_PARSE_ERROR: return "Parse error";
                case ERR_INVALID_PARAMETER: return "Invalid parameter";
                case ERR_INVALID_DATA: return "Invalid data";
                case ERR_BUSY: return "Busy";
                case ERR_ALREADY_EXISTS: return "Already exists";
                case ERR_DOES_NOT_EXIST: return "Does not exist";
                case ERR_CONNECTION_ERROR: return "Connection error";
            }
            return "(invalid error code)";
        }

        // ------------------------------------------------------------------ output
        /// <summary>Where print() / push_error() / push_warning() go (the Unity client points these at Debug.Log).</summary>
        public static Action<string> PrintSink = s => Console.WriteLine(s);
        public static Action<string> ErrorSink = s => Console.Error.WriteLine("ERROR: " + s);
        public static Action<string> WarningSink = s => Console.Error.WriteLine("WARNING: " + s);

        public static void Print(params Var[] parts) => PrintSink?.Invoke(Concat(parts, ""));
        public static void Prints(params Var[] parts) => PrintSink?.Invoke(Concat(parts, " "));
        public static void Printt(params Var[] parts) => PrintSink?.Invoke(Concat(parts, "\t"));
        public static void PrintRich(params Var[] parts) => PrintSink?.Invoke(Concat(parts, ""));
        public static void PrintErr(params Var[] parts) => ErrorSink?.Invoke(Concat(parts, ""));
        public static void PushError(params Var[] parts) => ErrorSink?.Invoke(Concat(parts, ""));
        public static void PushWarning(params Var[] parts) => WarningSink?.Invoke(Concat(parts, ""));

        static string Concat(Var[] parts, string sep)
        {
            if (parts.Length == 1) return GFormat.Str(parts[0]);
            var sb = new StringBuilder();
            for (int i = 0; i < parts.Length; i++)
            {
                if (i > 0) sb.Append(sep);
                sb.Append(GFormat.Str(parts[i]));
            }
            return sb.ToString();
        }

        // ------------------------------------------------------------------ conversions
        /// <summary>str(a, b, ...): each as str() writes it, joined.</summary>
        public static string Str(params Var[] parts) => Concat(parts, "");
        public static string Str(Var v) => GFormat.Str(v);
        public static string Str(string s) => s ?? "<null>";
        public static string Str(long v) => GFormat.Itos(v);
        public static string Str(int v) => GFormat.Itos(v);
        public static string Str(double v) => GFormat.NumReal(v, true);
        public static string Str(bool v) => v ? "true" : "false";

        /// <summary>int(x).</summary>
        public static int Int(Var v) => v.AsInt();
        public static int Int(double v) => unchecked((int)Var.DoubleToLong(v));
        public static int Int(string s) => unchecked((int)GStr.ToInt(s));
        public static int Int(bool b) => b ? 1 : 0;
        public static long Long(Var v) => v.AsLong();
        public static long Long(double v) => Var.DoubleToLong(v);
        /// <summary>float(x).</summary>
        public static double Float(Var v) => v.AsFloat();
        public static double Float(string s) => GStr.ToFloat(s);
        /// <summary>bool(x).</summary>
        public static bool Bool(Var v) => v.Truthy;

        /// <summary>len(x): string, array, dictionary, packed array.</summary>
        public static int Len(Var v)
        {
            if (v.IsString || v.IsArr || v.IsDict || (v.IsObj && v.Obj is ICollection)) return v.Size();
            PushError("len() of a value of type '" + TypeString(v.GodotType) + "'.");
            return 0;
        }

        public static int TypeOf(Var v) => v.GodotType;

        /// <summary>hash(x): Godot's exact Variant hash (seeds and picks derived from it match the Godot build).</summary>
        public static long Hash(Var v) => v.GodotHash();

        /// <summary>is_instance_valid(obj): not null and not freed.</summary>
        public static bool IsInstanceValid(object o) => o != null && !(o is IGodotObject g && g.IsFreed) && !(o is Var v && v.IsNull);
        public static bool IsInstanceValid(Var v) => !v.IsNull;

        /// <summary>`fmt % args`.</summary>
        public static string Fmt(string fmt, params Var[] args) => GFormat.Sprintf(fmt, args);

        /// <summary>range(n), range(from, to), range(from, to, step).</summary>
        public static IEnumerable<int> Range(int n) { for (int i = 0; i < n; i++) yield return i; }
        public static IEnumerable<int> Range(int from, int to, int step = 1)
        {
            if (step > 0) for (int i = from; i < to; i += step) yield return i;
            else if (step < 0) for (int i = from; i > to; i += step) yield return i;
        }

        // ------------------------------------------------------------------ the global random generator
        /// <summary>Math::default_rand: randf(), randi(), shuffle(), pick_random()... (randomized at start, as Godot does).</summary>
        public static readonly Rng GlobalRng = new Rng((ulong)DateTime.UtcNow.Ticks * 6364136223846793005UL + 1442695040888963407UL);

        public static void Randomize() => GlobalRng.Seed = (ulong)DateTime.UtcNow.Ticks * GlobalRng.State + 1442695040888963407UL;
        public static void Seed(long s) => GlobalRng.Seed = unchecked((ulong)s);
        public static long Randi() => GlobalRng.Next();
        /// <summary>randf(): Math::randf -- one draw over UINT32_MAX in float (not RandomNumberGenerator.randf's way).</summary>
        public static double Randf() => (float)GlobalRng.Next() / (float)uint.MaxValue;
        public static double RandfRange(double from, double to) => GlobalRng.Randd() * (to - from) + from;
        public static int RandiRange(long from, long to) => GlobalRng.RandiRange((int)from, (int)to);

        public static double Randfn(double mean = 0.0, double deviation = 1.0)
        {
            double temp = GlobalRng.Randd();
            if (temp < CMP_EPSILON) temp += CMP_EPSILON;
            return mean + deviation * (Math.Cos(TAU * GlobalRng.Randd()) * Math.Sqrt(-2.0 * Math.Log(temp)));
        }

        // ------------------------------------------------------------------ more of @GlobalScope's math
        public static double Clampf(double v, double lo, double hi) => Clamp(v, lo, hi);
        public static int Clampi(long v, long lo, long hi) => ClampI(v, lo, hi);
        public static double Maxf(double a, double b) => Max(a, b);
        public static double Minf(double a, double b) => Min(a, b);
        public static int Maxi(long a, long b) => (int)(a > b ? a : b);
        public static int Mini(long a, long b) => (int)(a < b ? a : b);
        public static double Absf(double v) => Math.Abs(v);
        public static int Absi(long v) => (int)(v < 0 ? -v : v);
        public static double Signf(double v) => Sign(v);
        public static int Signi(long v) => v > 0 ? 1 : v < 0 ? -1 : 0;
        public static double Floorf(double v) => Math.Floor(v);
        public static double Ceilf(double v) => Math.Ceiling(v);
        public static double Roundf(double v) => Round(v);
        public static int Floori(double v) => FloorI(v);
        public static int Ceili(double v) => CeilI(v);
        public static int Roundi(double v) => RoundI(v);
        public static double Lerpf(double from, double to, double w) => Lerp(from, to, w);
        public static double Tan(double v) => Math.Tan(v);
        public static double Atan(double v) => Math.Atan(v);
        public static double Sinh(double v) => Math.Sinh(v);
        public static double Cosh(double v) => Math.Cosh(v);
        public static double Tanh(double v) => Math.Tanh(v);
        public static double Log(double v) => Math.Log(v);
        public static double RadToDeg(double r) => r * (180.0 / PI);
        public static bool IsZeroApprox(double v) => Math.Abs(v) < CMP_EPSILON;
        public static bool IsFinite(double v) => !double.IsNaN(v) && !double.IsInfinity(v);
        public static bool IsNan(double v) => double.IsNaN(v);
        public static bool IsInf(double v) => double.IsInfinity(v);
        public static double InverseLerp(double from, double to, double v) => (v - from) / (to - from);
        public static double Remap(double v, double istart, double istop, double ostart, double ostop) =>
            Lerp(ostart, ostop, InverseLerp(istart, istop, v));
        public static double Fract(double v) => v - Math.Floor(v);
        public static double Pingpong(double v, double length) =>
            length != 0.0 ? Math.Abs(Fract((v - length) / (length * 2.0)) * length * 2.0 - length) : 0.0;
        public static double LinearToDb(double linear) => Math.Log(linear) * 8.6858896380650365530225783783321;
        public static double DbToLinear(double db) => Math.Exp(db * 0.11512925464970228420089957273422);
        public static double Snappedf(double v, double step) => Snapped(v, step);
        public static long Snappedi(double v, long step) => step != 0 ? (long)(Math.Floor(v / step + 0.5) * step) : (long)v;

        public static double Wrapf(double v, double min, double max)
        {
            double range = max - min;
            if (IsZeroApprox(range)) return min;
            double result = v - (range * Math.Floor((v - min) / range));
            if (IsEqualApprox(result, max)) return min;
            return result;
        }

        public static long Wrapi(long v, long min, long max)
        {
            long range = max - min;
            return range == 0 ? min : min + ((((v - min) % range) + range) % range);
        }

        public static double Ease(double x, double c)
        {
            if (x < 0) x = 0;
            else if (x > 1.0) x = 1.0;
            if (c > 0)
            {
                if (c < 1.0) return 1.0 - Math.Pow(1.0 - x, 1.0 / c);
                return Math.Pow(x, c);
            }
            if (c < 0)
            {
                if (x < 0.5) return Math.Pow(x * 2.0, -c) * 0.5;
                return (1.0 - Math.Pow(1.0 - (x - 0.5) * 2.0, -c)) * 0.5 + 0.5;
            }
            return 0;
        }

        public static double BezierInterpolate(double start, double c1, double c2, double end, double t)
        {
            double omt = 1.0 - t, omt2 = omt * omt, omt3 = omt2 * omt, t2 = t * t, t3 = t2 * t;
            return start * omt3 + c1 * omt2 * t * 3.0 + c2 * omt * t2 * 3.0 + end * t3;
        }

        public static int StepDecimals(double step)
        {
            const int maxn = 10;
            double[] sd = { 0.9999, 0.09999, 0.009999, 0.0009999, 0.00009999, 0.000009999, 0.0000009999, 0.00000009999, 0.000000009999, 0.0000000009999 };
            double abs = Math.Abs(step);
            double decs = abs - (int)abs;
            for (int i = 0; i < maxn; i++) if (decs >= sd[i]) return i;
            return 0;
        }

        public static long NearestPo2(long v)
        {
            if (v <= 0) return 0;
            long p = 1;
            while (p < v) p <<= 1;
            return p;
        }

        /// <summary>max(a, b, ...) / min(...) on Variants: int if every argument is an int.</summary>
        public static Var MaxV(params Var[] a)
        {
            Var m = a[0];
            for (int i = 1; i < a.Length; i++) if (Var.Less(m, a[i])) m = a[i];
            return AllInt(a) ? m : (Var)m.AsFloat();
        }

        public static Var MinV(params Var[] a)
        {
            Var m = a[0];
            for (int i = 1; i < a.Length; i++) if (Var.Less(a[i], m)) m = a[i];
            return AllInt(a) ? m : (Var)m.AsFloat();
        }

        static bool AllInt(Var[] a)
        {
            foreach (var x in a) if (!x.IsInt) return false;
            return true;
        }
    }

    /// <summary>weakref(obj): get_ref() is the object while it lives, null after it's freed.</summary>
    public sealed class WeakRef
    {
        readonly WeakReference _w;
        public WeakRef(object o) { _w = new WeakReference(o); }
        public object GetRef()
        {
            var o = _w.Target;
            if (o is IGodotObject g && g.IsFreed) return null;
            return o;
        }
    }
}
