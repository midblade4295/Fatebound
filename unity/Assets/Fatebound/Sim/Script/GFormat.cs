// GDScript's text of values: str() (Variant::stringify), String::num / num_real (printf's exact decimal rounding,
// half to even, then trailing zeros dropped), and the `%` operator (String::sprintf) -- what labels show must read
// the same as in the Godot build.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Numerics;
using System.Text;

namespace Fatebound.Sim
{
    public static class GFormat
    {
        const int MAX_DECIMALS = 32;

        // ------------------------------------------------------------------ str()
        public static string Str(Var v) => Str(v, 0);

        static string Str(Var v, int depth)
        {
            switch (v.Type)
            {
                case VT.Nil: return "<null>";
                case VT.Bool: return v.Truthy ? "true" : "false";
                case VT.Int: return v.AsLong().ToString(CultureInfo.InvariantCulture);
                case VT.Float: return NumReal(v.AsFloat(), true);
                case VT.String: return v.AsString();
                case VT.Vec2: { var p = v.AsVec2(); return "(" + NumRealF(p.x, true) + ", " + NumRealF(p.y, true) + ")"; }
                case VT.Vec2i: { var p = v.AsVec2i(); return "(" + p.x + ", " + p.y + ")"; }
                case VT.Vec3: { var p = v.AsVec3(); return "(" + NumRealF(p.x, true) + ", " + NumRealF(p.y, true) + ", " + NumRealF(p.z, true) + ")"; }
                case VT.Dict:
                    {
                        if (depth > 100) return "{ ... }";
                        var d = v.AsDict();
                        var sb = new StringBuilder("{ ");
                        bool first = true;
                        foreach (var kv in d.Pairs())
                        {
                            if (!first) sb.Append(", ");
                            first = false;
                            sb.Append(Clean(kv.Key, depth + 1)).Append(": ").Append(Clean(kv.Value, depth + 1));
                        }
                        sb.Append(" }");
                        return sb.ToString();
                    }
                case VT.Arr:
                    {
                        if (depth > 100) return "[...]";
                        var a = v.AsArr();
                        var sb = new StringBuilder("[");
                        for (int i = 0; i < a.Size(); i++)
                        {
                            if (i > 0) sb.Append(", ");
                            sb.Append(Clean(a[i], depth + 1));
                        }
                        sb.Append("]");
                        return sb.ToString();
                    }
            }
            var o = v.Obj;
            switch (o)
            {
                case IGodotObject go: return go.IsFreed ? "<Freed Object>" : o.ToString();
                case IGodotValue gv: return gv.GodotStr();
                case string s: return s;
                case IList list:
                    {
                        var sb = new StringBuilder("[");
                        for (int i = 0; i < list.Count; i++)
                        {
                            if (i > 0) sb.Append(", ");
                            sb.Append(Clean(Var.Of(list[i]), depth + 1));
                        }
                        sb.Append("]");
                        return sb.ToString();
                    }
            }
            return o?.ToString() ?? "<null>";
        }

        /// <summary>A value as it appears inside a printed dictionary/array: strings quoted and C-escaped.</summary>
        public static string Clean(Var v) => Clean(v, 0);

        static string Clean(Var v, int depth)
        {
            if (v.Type == VT.String) return "\"" + GStr.CEscape(v.AsString()) + "\"";
            return Str(v, depth);
        }

        // ------------------------------------------------------------------ numbers
        public static string Itos(long v) => v.ToString(CultureInfo.InvariantCulture);

        /// <summary>String::num_real(double, trailing): "1.0" for whole numbers, else 14 significant decimals' worth.</summary>
        public static string NumReal(double v, bool trailing = true)
        {
            if (double.IsNaN(v) || double.IsInfinity(v)) return Num(v, 0);
            if (v >= -9.2233720368547758e18 && v < 9.2233720368547758e18 && v == (double)(long)v)
                return ((long)v).ToString(CultureInfo.InvariantCulture) + (trailing ? ".0" : "");
            int decimals = 14;
            double a = Math.Abs(v);
            if (a > 10) decimals -= (int)Math.Floor(Math.Log10(a));
            return Num(v, decimals);
        }

        /// <summary>String::num_real(float, trailing): Vector2/3 components (6 decimals' worth).</summary>
        public static string NumRealF(float v, bool trailing = true)
        {
            if (float.IsNaN(v) || float.IsInfinity(v)) return Num(v, 0);
            if (v >= -9.2233720368547758e18f && v < 9.2233720368547758e18f && v == (float)(long)v)
                return ((long)v).ToString(CultureInfo.InvariantCulture) + (trailing ? ".0" : "");
            int decimals = 6;
            float a = Math.Abs(v);
            if (a > 10) decimals -= (int)Math.Floor(Math.Log10(a));
            return Num(v, decimals);
        }

        /// <summary>String::num(value, decimals): printf "%.Nf", trailing zeros dropped (one kept after the point).
        /// decimals < 0: Godot's default (14 minus the magnitude).</summary>
        public static string Num(double v, int decimals = -1)
        {
            if (double.IsNaN(v)) return "nan";
            if (double.IsInfinity(v)) return v < 0 ? "-inf" : "inf";
            if (decimals < 0)
            {
                decimals = 14;
                double a = Math.Abs(v);
                if (a > 10) decimals -= (int)Math.Floor(Math.Log10(a));
            }
            if (decimals > MAX_DECIMALS) decimals = MAX_DECIMALS;
            string s = Printf(v, decimals < 0 ? 6 : decimals);       // (a still-negative count makes the format "%lf")
            if (s.IndexOf('.') >= 0)
            {
                int z = s.Length - 1;
                while (z > 0)
                {
                    if (s[z] == '0') z--;
                    else if (s[z] == '.') { z++; break; }
                    else break;
                }
                s = s.Substring(0, z + 1);
            }
            return s;
        }

        /// <summary>printf("%.Nf", v) exactly: the binary value's decimal expansion rounded half to even.</summary>
        public static string Printf(double v, int decimals)
        {
            if (double.IsNaN(v)) return "nan";
            if (double.IsInfinity(v)) return v < 0 ? "-inf" : "inf";
            bool neg = BitConverter.DoubleToInt64Bits(v) < 0;
            string s = FixedAbs(Math.Abs(v), decimals);
            return neg ? "-" + s : s;
        }

        static readonly ulong[] Pow10U = { 1, 10, 100, 1000 };

        static string FixedAbs(double a, int n)
        {
            long bits = BitConverter.DoubleToInt64Bits(a);
            int bexp = (int)((bits >> 52) & 0x7FF);
            ulong frac = (ulong)bits & 0xFFFFFFFFFFFFFUL;
            ulong m;
            int e;
            if (bexp == 0) { m = frac; e = -1074; }
            else { m = frac | (1UL << 52); e = bexp - 1075; }
            string digits;
            if (m == 0) digits = "0";
            else if (e >= 0)
            {
                if (e <= 10) digits = (m << e).ToString(CultureInfo.InvariantCulture);
                else digits = (new BigInteger(m) << e).ToString(CultureInfo.InvariantCulture);
                if (n > 0) digits += new string('0', n);
            }
            else
            {
                int k = -e;
                if (n <= 3 && k <= 62)
                {
                    ulong num = m * Pow10U[n];          // < 2^53 * 1000 < 2^63
                    ulong q = num >> k;
                    ulong r = num & ((1UL << k) - 1);
                    ulong half = 1UL << (k - 1);
                    if (r > half || (r == half && (q & 1) != 0)) q++;
                    digits = q.ToString(CultureInfo.InvariantCulture);
                }
                else
                {
                    BigInteger num = new BigInteger(m) * BigInteger.Pow(10, n);
                    BigInteger q = num >> k;
                    BigInteger r = num - (q << k);
                    BigInteger half = BigInteger.One << (k - 1);
                    int c = r.CompareTo(half);
                    if (c > 0 || (c == 0 && !q.IsEven)) q += 1;
                    digits = q.ToString(CultureInfo.InvariantCulture);
                }
            }
            if (n == 0) return digits;
            if (digits.Length <= n) digits = new string('0', n - digits.Length + 1) + digits;
            return digits.Substring(0, digits.Length - n) + "." + digits.Substring(digits.Length - n);
        }

        /// <summary>String::num_scientific: the shortest text that reads back as the same double (grisu2's layout:
        /// plain digits from 1e-5 up to 1e15, exponent form "1.5e+20" beyond).</summary>
        public static string NumScientific(double v)
        {
            if (double.IsNaN(v) || double.IsInfinity(v)) return Num(v, 0);
            if (v == 0) return BitConverter.DoubleToInt64Bits(v) < 0 ? "-0.0" : "0.0";
            string r = Shortest(v, out int exp10, out bool neg);    // digits d1d2..dn, value = 0.d1..dn * 10^exp10
            int n = r.Length, k = exp10;
            var sb = new StringBuilder();
            if (neg) sb.Append('-');
            if (k >= n && k <= 15)
            {
                sb.Append(r).Append('0', k - n).Append(".0");
            }
            else if (k > 0 && k <= 15)
            {
                sb.Append(r, 0, k).Append('.').Append(r, k, n - k);
            }
            else if (k > -5 && k <= 0)
            {
                sb.Append("0.").Append('0', -k).Append(r);
            }
            else
            {
                sb.Append(r[0]);
                if (n > 1) sb.Append('.').Append(r, 1, n - 1);
                int ee = k - 1;
                sb.Append('e').Append(ee < 0 ? '-' : '+');
                ee = Math.Abs(ee);
                if (ee < 10) sb.Append('0');
                sb.Append(ee.ToString(CultureInfo.InvariantCulture));
            }
            return sb.ToString();
        }

        static string Shortest(double v, out int exp10, out bool neg)
        {
            neg = v < 0;
            double a = Math.Abs(v);
            for (int p = 1; p <= 17; p++)
            {
                string s = a.ToString("E" + (p - 1), CultureInfo.InvariantCulture);
                if (double.Parse(s, CultureInfo.InvariantCulture) == a || p == 17)
                {
                    int epos = s.IndexOf('E');
                    string mant = s.Substring(0, epos).Replace(".", "");
                    int ex = int.Parse(s.Substring(epos + 1), CultureInfo.InvariantCulture);
                    mant = mant.TrimEnd('0');
                    if (mant.Length == 0) mant = "0";
                    exp10 = ex + 1;
                    return mant;
                }
            }
            exp10 = 0;
            return "0";
        }

        // ------------------------------------------------------------------ the % operator
        /// <summary>`fmt % x`: an array's elements are the arguments, anything else is the one argument.</summary>
        public static string SprintfOp(string fmt, Var arg)
        {
            List<Var> args;
            if (arg.IsArr) args = arg.AsArr().List;
            else args = new List<Var> { arg };
            string r = Sprintf(fmt, args, out bool err);
            if (err) GD.PushError("String formatting error: " + r);
            return r;
        }

        public static string Sprintf(string fmt, params Var[] args)
        {
            string r = Sprintf(fmt, (IList<Var>)args, out bool err);
            if (err) GD.PushError("String formatting error: " + r);
            return r;
        }

        /// <summary>String::sprintf, character for character (error: the message instead of the text).</summary>
        public static string Sprintf(string self, IList<Var> values, out bool error)
        {
            error = true;
            var used = new bool[values.Count];
            var formatted = new StringBuilder();
            bool inFormat = false;
            int valueIndex = 0;
            int selectedIndex = -1;
            int minChars = 0;
            int minDecimals = 0;
            bool inDecimals = false;
            bool padWithZeros = false;
            bool leftJustified = false;
            bool showSign = false;
            bool asUnsigned = false;

            for (int ci = 0; ci < self.Length; ci++)
            {
                char c = self[ci];
                if (inFormat)
                {
                    switch (c)
                    {
                        case '%':
                            formatted.Append(c);
                            inFormat = false;
                            break;
                        case 'd':
                        case 'o':
                        case 'x':
                        case 'X':
                            {
                                int index = selectedIndex >= 0 ? selectedIndex : valueIndex;
                                if (index >= values.Count) return "not enough arguments for format string";
                                if (!values[index].IsNum) return "a number is required";
                                long value = values[index].AsLong();
                                int nb = 16;
                                bool capitalize = false;
                                if (c == 'd') nb = 10;
                                else if (c == 'o') nb = 8;
                                else if (c == 'X') capitalize = true;
                                string str;
                                if (!asUnsigned)
                                {
                                    if (value == long.MinValue) str = NumInt64(value, nb, capitalize).TrimStart('-');
                                    else str = NumInt64(Math.Abs(value), nb, capitalize);
                                }
                                else
                                {
                                    ulong uv = unchecked((ulong)value);
                                    if (nb == 16 && value < 0 && value >= int.MinValue) uv &= 0xffffffff;
                                    str = NumUint64(uv, nb, capitalize);
                                }
                                int numberLen = str.Length;
                                bool negative = value < 0 && !asUnsigned;
                                int padCount = (negative || showSign) ? minChars - 1 : minChars;
                                string padChar = padWithZeros ? "0" : " ";
                                str = leftJustified ? GStr.Rpad(str, padCount, padChar) : GStr.Lpad(str, padCount, padChar);
                                if (showSign || negative)
                                {
                                    string sign = negative ? "-" : "+";
                                    if (leftJustified) str = str.Insert(0, sign);
                                    else str = str.Insert(padWithZeros ? 0 : str.Length - numberLen, sign);
                                }
                                formatted.Append(str);
                                if (selectedIndex == -1) ++valueIndex;
                                used[index] = true;
                                inFormat = false;
                                break;
                            }
                        case 'f':
                            {
                                int index = selectedIndex >= 0 ? selectedIndex : valueIndex;
                                if (index >= values.Count) return "not enough arguments for format string";
                                if (!values[index].IsNum) return "a number is required";
                                double value = values[index].AsFloat();
                                bool isNegative = BitConverter.DoubleToInt64Bits(value) < 0;
                                string str = Num(Math.Abs(value), minDecimals);
                                bool finite = !double.IsNaN(value) && !double.IsInfinity(value);
                                if (finite) str = GStr.PadDecimals(str, minDecimals);
                                int initialLen = str.Length;
                                int padCount = (isNegative || showSign) ? minChars - 1 : minChars;
                                string padChar = (padWithZeros && finite) ? "0" : " ";
                                str = leftJustified ? GStr.Rpad(str, padCount, padChar) : GStr.Lpad(str, padCount, padChar);
                                if (showSign || isNegative)
                                {
                                    string sign = isNegative ? "-" : "+";
                                    if (leftJustified) str = str.Insert(0, sign);
                                    else str = str.Insert(padWithZeros ? 0 : str.Length - initialLen, sign);
                                }
                                formatted.Append(str);
                                if (selectedIndex == -1) ++valueIndex;
                                used[index] = true;
                                inFormat = false;
                                break;
                            }
                        case 'v':
                            {
                                int index = selectedIndex >= 0 ? selectedIndex : valueIndex;
                                if (index >= values.Count) return "not enough arguments for format string";
                                double[] comps;
                                var vv = values[index];
                                if (vv.IsVec2) { var p = vv.AsVec2(); comps = new double[] { p.x, p.y }; }
                                else if (vv.IsVec2i) { var p = vv.AsVec2i(); comps = new double[] { p.x, p.y }; }
                                else if (vv.IsVec3) { var p = vv.AsVec3(); comps = new double[] { p.x, p.y, p.z }; }
                                else return "%v requires a vector type (Vector2/3/4/2i/3i/4i)";
                                var sb = new StringBuilder("(");
                                for (int i = 0; i < comps.Length; i++)
                                {
                                    double val = comps[i];
                                    string ns = Num(Math.Abs(val), minDecimals);
                                    bool finite = !double.IsNaN(val) && !double.IsInfinity(val);
                                    if (finite) ns = GStr.PadDecimals(ns, minDecimals);
                                    int initialLen = ns.Length;
                                    int padCount = val < 0 ? minChars - 1 : minChars;
                                    string padChar = (padWithZeros && finite) ? "0" : " ";
                                    ns = leftJustified ? GStr.Rpad(ns, padCount, padChar) : GStr.Lpad(ns, padCount, padChar);
                                    if (val < 0)
                                    {
                                        if (leftJustified) ns = ns.Insert(0, "-");
                                        else ns = ns.Insert(padWithZeros ? 0 : ns.Length - initialLen, "-");
                                    }
                                    sb.Append(ns);
                                    if (i < comps.Length - 1) sb.Append(", ");
                                }
                                sb.Append(")");
                                formatted.Append(sb);
                                if (selectedIndex == -1) ++valueIndex;
                                used[index] = true;
                                inFormat = false;
                                break;
                            }
                        case 's':
                            {
                                int index = selectedIndex >= 0 ? selectedIndex : valueIndex;
                                if (index >= values.Count) return "not enough arguments for format string";
                                string str = Str(values[index]);
                                str = leftJustified ? GStr.Rpad(str, minChars) : GStr.Lpad(str, minChars);
                                formatted.Append(str);
                                if (selectedIndex == -1) ++valueIndex;
                                used[index] = true;
                                inFormat = false;
                                break;
                            }
                        case 'c':
                            {
                                int index = selectedIndex >= 0 ? selectedIndex : valueIndex;
                                if (index >= values.Count) return "not enough arguments for format string";
                                string str;
                                if (values[index].IsNum)
                                {
                                    int value = values[index].AsInt();
                                    if (value < 0) return "unsigned integer is lower than minimum";
                                    if (value >= 0xd800 && value <= 0xdfff) return "unsigned integer is invalid Unicode character";
                                    if (value > 0x10ffff) return "unsigned integer is greater than maximum";
                                    str = char.ConvertFromUtf32(value);
                                }
                                else if (values[index].IsString)
                                {
                                    str = values[index].AsString();
                                    if (GStr.Length(str) != 1) return "%c requires number or single-character string";
                                }
                                else return "%c requires number or single-character string";
                                str = leftJustified ? GStr.Rpad(str, minChars) : GStr.Lpad(str, minChars);
                                formatted.Append(str);
                                if (selectedIndex == -1) ++valueIndex;
                                used[index] = true;
                                inFormat = false;
                                break;
                            }
                        case '-': leftJustified = true; break;
                        case '+': showSign = true; break;
                        case 'u': asUnsigned = true; break;
                        case '0':
                        case '1':
                        case '2':
                        case '3':
                        case '4':
                        case '5':
                        case '6':
                        case '7':
                        case '8':
                        case '9':
                            {
                                int n = c - '0';
                                if (inDecimals)
                                {
                                    minDecimals *= 10;
                                    minDecimals += n;
                                }
                                else
                                {
                                    if (c == '0' && minChars == 0)
                                    {
                                        if (!leftJustified) padWithZeros = true;
                                    }
                                    else
                                    {
                                        minChars *= 10;
                                        minChars += n;
                                    }
                                }
                                break;
                            }
                        case '$':
                            if (minChars > 0) selectedIndex = minChars - 1;
                            minChars = 0;
                            padWithZeros = false;
                            break;
                        case '.':
                            if (inDecimals) return "too many decimal points in format";
                            inDecimals = true;
                            minDecimals = 0;
                            break;
                        case '*':
                            {
                                int index = selectedIndex >= 0 ? selectedIndex : valueIndex;
                                if (index >= values.Count) return "not enough arguments for format string";
                                var vv = values[index];
                                if (!vv.IsNum && !vv.IsVec2 && !vv.IsVec2i && !vv.IsVec3) return "* wants number or vector";
                                int size = vv.AsInt();
                                if (inDecimals) minDecimals = size; else minChars = size;
                                if (selectedIndex == -1) ++valueIndex;
                                used[index] = true;
                                break;
                            }
                        default:
                            return "unsupported format character";
                    }
                }
                else
                {
                    if (c == '%')
                    {
                        inFormat = true;
                        minChars = 0;
                        minDecimals = 6;
                        padWithZeros = false;
                        leftJustified = false;
                        showSign = false;
                        inDecimals = false;
                        selectedIndex = -1;
                    }
                    else formatted.Append(c);
                }
            }
            if (inFormat) return "incomplete format";
            foreach (var b in used) if (!b) return "not all arguments converted during string formatting";
            error = false;
            return formatted.ToString();
        }

        public static string NumInt64(long v, int b = 10, bool capitalize = false)
        {
            if (b == 10) return v.ToString(CultureInfo.InvariantCulture);
            bool neg = v < 0;
            ulong u = neg ? (ulong)(-(v + 1)) + 1 : (ulong)v;
            string s = NumUint64(u, b, capitalize);
            return neg ? "-" + s : s;
        }

        public static string NumUint64(ulong v, int b = 10, bool capitalize = false)
        {
            if (v == 0) return "0";
            var chars = new char[64];
            int p = 64;
            while (v > 0)
            {
                int d = (int)(v % (ulong)b);
                chars[--p] = (char)(d < 10 ? '0' + d : (capitalize ? 'A' : 'a') + d - 10);
                v /= (ulong)b;
            }
            return new string(chars, p, 64 - p);
        }
    }
}
