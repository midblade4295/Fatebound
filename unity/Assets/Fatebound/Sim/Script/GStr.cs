// Godot's String methods with their exact behaviour, as extension methods (s.BeginsWith(x), s.Substr(1, 2),
// s.ToInt()...). Where C#'s own string method does the same thing the port uses it: Contains, Replace, Insert,
// Remove (= erase), Split(delim) (= split with empty parts kept), ToUpperInvariant / ToLowerInvariant (to_upper /
// to_lower), Length. join is GStr.Join(sep, parts) (C# would read ", ".Join(...) as its static String.Join).
using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;

namespace Fatebound.Sim
{
    public static class GStr
    {
        // ------------------------------------------------------------------ slicing
        /// <summary>substr(from, chars): "" when from is out of range; chars -1 to the end.</summary>
        public static string Substr(this string s, int from, int chars = -1)
        {
            if (chars == -1) chars = s.Length - from;
            if (s.Length == 0 || from < 0 || from >= s.Length || chars <= 0) return "";
            if (from + chars > s.Length) chars = s.Length - from;
            return s.Substring(from, chars);
        }

        /// <summary>left(n): the first n characters; negative n drops that many from the end.</summary>
        public static string Left(this string s, int n)
        {
            if (n < 0) n = s.Length + n;
            if (n <= 0) return "";
            if (n >= s.Length) return s;
            return s.Substring(0, n);
        }

        /// <summary>right(n): the last n characters; negative n drops that many from the start.</summary>
        public static string Right(this string s, int n)
        {
            if (n < 0) n = s.Length + n;
            if (n <= 0) return "";
            if (n >= s.Length) return s;
            return s.Substring(s.Length - n);
        }

        public static int Find(this string s, string what, int from = 0)
        {
            if (from < 0 || from >= s.Length && what.Length > 0) return -1;
            if (what.Length == 0) return -1;
            return s.IndexOf(what, from, StringComparison.Ordinal);
        }

        public static int FindN(this string s, string what, int from = 0)
        {
            if (from < 0 || from >= s.Length || what.Length == 0) return -1;
            return s.IndexOf(what, from, StringComparison.OrdinalIgnoreCase);
        }

        public static int RFind(this string s, string what, int from = -1)
        {
            if (what.Length == 0) return -1;
            if (from < 0) from = s.Length - what.Length;
            else if (from > s.Length - what.Length) from = s.Length - what.Length;
            if (from < 0) return -1;
            int start = Math.Min(s.Length - 1, from + what.Length - 1);
            if (start < 0) return -1;
            return s.LastIndexOf(what, start, StringComparison.Ordinal);
        }

        public static bool BeginsWith(this string s, string prefix) => s.StartsWith(prefix, StringComparison.Ordinal);
        public static bool EndsWithG(this string s, string suffix) => s.EndsWith(suffix, StringComparison.Ordinal);

        public static string TrimPrefix(this string s, string prefix) =>
            prefix.Length > 0 && s.StartsWith(prefix, StringComparison.Ordinal) ? s.Substring(prefix.Length) : s;

        public static string TrimSuffix(this string s, string suffix) =>
            suffix.Length > 0 && s.EndsWith(suffix, StringComparison.Ordinal) ? s.Substring(0, s.Length - suffix.Length) : s;

        /// <summary>strip_edges(): every character up to U+0020 trimmed from the ends.</summary>
        public static string StripEdges(this string s, bool left = true, bool right = true)
        {
            int len = s.Length, beg = 0, end = len;
            if (left) while (beg < len && s[beg] <= 32) beg++;
            if (right) while (end > beg && s[end - 1] <= 32) end--;
            if (beg == 0 && end == len) return s;
            return s.Substring(beg, end - beg);
        }

        /// <summary>split(delimiter, allow_empty, maxsplit): "" splits into single characters.</summary>
        public static string[] Split(this string s, string delim, bool allowEmpty, int maxsplit = 0)
        {
            var ret = new List<string>();
            if (s.Length == 0)
            {
                if (allowEmpty) ret.Add("");
                return ret.ToArray();
            }
            int from = 0, len = s.Length;
            while (true)
            {
                int end;
                if (delim.Length == 0) end = from + 1;
                else
                {
                    end = s.IndexOf(delim, from, StringComparison.Ordinal);
                    if (end < 0) end = len;
                }
                if (allowEmpty || end > from)
                {
                    if (maxsplit <= 0) ret.Add(s.Substring(from, end - from));
                    else
                    {
                        if (maxsplit == ret.Count)
                        {
                            ret.Add(s.Substr(from, len));
                            break;
                        }
                        ret.Add(s.Substring(from, end - from));
                    }
                }
                if (end == len) break;
                from = end + delim.Length;
            }
            return ret.ToArray();
        }

        /// <summary>split_floats(delimiter, allow_empty).</summary>
        public static double[] SplitFloats(this string s, string delim, bool allowEmpty = true)
        {
            var parts = s.Split(delim, allowEmpty);
            var r = new double[parts.Length];
            for (int i = 0; i < parts.Length; i++) r[i] = ToFloat(parts[i]);
            return r;
        }

        /// <summary>get_slice(delimiter, n): the n-th part ("" past the end; the whole string if no delimiter).</summary>
        public static string GetSlice(this string s, string delim, int slice)
        {
            if (s.Length == 0 || delim.Length == 0 || slice < 0) return "";
            if (s.IndexOf(delim, StringComparison.Ordinal) < 0) return s;
            int pos = 0, prev = 0, i = 0;
            while (true)
            {
                pos = s.IndexOf(delim, pos, StringComparison.Ordinal);
                if (pos == -1) pos = s.Length;
                if (slice == i) return s.Substring(prev, pos - prev);
                if (pos == s.Length) break;
                pos += delim.Length;
                prev = pos;
                i++;
            }
            return "";
        }

        public static int GetSliceCount(this string s, string delim)
        {
            if (s.Length == 0 || delim.Length == 0) return 0;
            int pos = 0, slices = 1;
            while ((pos = s.IndexOf(delim, pos, StringComparison.Ordinal)) >= 0)
            {
                slices++;
                pos += delim.Length;
            }
            return slices;
        }

        /// <summary>sep.join(parts): each part as str() gives it.</summary>
        public static string Join(string sep, IEnumerable parts)
        {
            var sb = new StringBuilder();
            bool first = true;
            foreach (var p in parts)
            {
                if (!first) sb.Append(sep);
                first = false;
                sb.Append(p is string ps ? ps : p is Var v ? GFormat.Str(v) : GFormat.Str(Var.Of(p)));
            }
            return sb.ToString();
        }

        public static int Count(this string s, string what, int from = 0, int to = 0)
        {
            if (what.Length == 0) return 0;
            int len = s.Length;
            if (to <= 0 || to > len) to = len;
            if (from < 0 || from >= to) return 0;
            int c = 0, pos = from;
            while (true)
            {
                pos = s.IndexOf(what, pos, StringComparison.Ordinal);
                if (pos < 0 || pos + what.Length > to) break;
                c++;
                pos += what.Length;
            }
            return c;
        }

        public static string Repeat(this string s, int n)
        {
            if (n <= 0 || s.Length == 0) return "";
            var sb = new StringBuilder(s.Length * n);
            for (int i = 0; i < n; i++) sb.Append(s);
            return sb.ToString();
        }

        public static string Reverse(this string s)
        {
            var a = s.ToCharArray();
            Array.Reverse(a);
            return new string(a);
        }

        /// <summary>unicode_at(i): the code at i (0 past the end).</summary>
        public static int UnicodeAt(this string s, int i) => (uint)i < (uint)s.Length ? s[i] : 0;

        /// <summary>length() in Unicode code points (C#'s Length counts UTF-16 units; equal for anything but emoji).</summary>
        public static int Length(string s)
        {
            int n = 0;
            for (int i = 0; i < s.Length; i++)
            {
                if (char.IsHighSurrogate(s[i]) && i + 1 < s.Length && char.IsLowSurrogate(s[i + 1])) i++;
                n++;
            }
            return n;
        }

        public static bool IsEmpty(this string s) => s.Length == 0;

        // ------------------------------------------------------------------ padding
        public static string Lpad(string s, int min, string ch = " ")
        {
            int n = min - s.Length;
            if (n <= 0) return s;
            return ch.Repeat(n) + s;
        }

        public static string Rpad(string s, int min, string ch = " ")
        {
            int n = min - s.Length;
            if (n <= 0) return s;
            return s + ch.Repeat(n);
        }

        public static string LPad(this string s, int min, string ch = " ") => Lpad(s, min, ch);
        public static string RPad(this string s, int min, string ch = " ") => Rpad(s, min, ch);

        public static string PadDecimals(this string s, int digits)
        {
            int c = s.IndexOf('.');
            if (c == -1)
            {
                if (digits <= 0) return s;
                s += ".";
                c = s.Length - 1;
            }
            else if (digits <= 0) return s.Substring(0, c);
            if (s.Length - (c + 1) > digits) return s.Substring(0, c + digits + 1);
            return s + new string('0', digits - s.Length + (c + 1));
        }

        public static string PadZeros(this string s, int digits)
        {
            int end = s.IndexOf('.');
            if (end == -1) end = s.Length;
            if (end == 0) return s;
            int begin = 0;
            while (begin < end && !(s[begin] >= '0' && s[begin] <= '9')) begin++;
            int add = digits - (end - begin);
            if (add <= 0) return s;
            return s.Insert(begin, new string('0', add));
        }

        // ------------------------------------------------------------------ numbers
        /// <summary>to_int(): the digits before the first '.', anything else skipped ("1x2" -> 12), a '-' before
        /// the first digit flips the sign.</summary>
        public static long ToInt(this string s)
        {
            if (s.Length == 0) return 0;
            int to = s.IndexOf('.');
            if (to < 0) to = s.Length;
            ulong integer = 0;
            int digits = 0;
            bool positive = true;
            for (int i = 0; i < to; i++)
            {
                char c = s[i];
                if (c >= '0' && c <= '9')
                {
                    if (digits > 18)
                    {
                        bool overflow = (integer > long.MaxValue / 10) || (integer == long.MaxValue / 10 && ((positive && c > '7') || (!positive && c > '8')));
                        if (overflow)
                        {
                            GD.PushError("Cannot represent " + s + " as a 64-bit signed integer.");
                            return positive ? long.MaxValue : long.MinValue;
                        }
                    }
                    integer = integer * 10 + (ulong)(c - '0');
                    ++digits;
                }
                else if (integer == 0 && c == '-') positive = !positive;
            }
            return positive ? unchecked((long)integer) : unchecked((long)(integer * ulong.MaxValue));
        }

        /// <summary>to_float(): Godot's own strtod (its rounding, not the correctly rounded one).</summary>
        public static double ToFloat(this string s)
        {
            if (s.Length == 0) return 0;
            return Strtod(s, 0, out _);
        }

        /// <summary>built_in_strtod: parses at pos, end = the index after the number.</summary>
        public static double Strtod(string str, int pos, out int end)
        {
            const int maxExponent = 511;
            double[] powersOf10 = { 10.0, 100.0, 1.0e4, 1.0e8, 1.0e16, 1.0e32, 1.0e64, 1.0e128, 1.0e256 };
            bool sign, expSign = false;
            double fraction, dblExp;
            int exp = 0, fracExp, mantSize, decPt, pExp;
            int p = pos;
            int n = str.Length;
            char At(int i) => i < n ? str[i] : '\0';

            while (At(p) == ' ' || At(p) == '\t' || At(p) == '\n') p++;
            if (At(p) == '-') { sign = true; p++; }
            else
            {
                if (At(p) == '+') p++;
                sign = false;
            }

            decPt = -1;
            for (mantSize = 0; ; mantSize++)
            {
                char c = At(p);
                if (!(c >= '0' && c <= '9'))
                {
                    if (c != '.' || decPt >= 0) break;
                    decPt = mantSize;
                }
                p++;
            }

            pExp = p;
            p -= mantSize;
            if (decPt < 0) decPt = mantSize;
            else mantSize -= 1;
            if (mantSize > 18)
            {
                fracExp = decPt - 18;
                mantSize = 18;
            }
            else fracExp = decPt - mantSize;

            if (mantSize == 0)
            {
                fraction = 0.0;
                p = pos;
                goto done;
            }
            else
            {
                int frac1 = 0, frac2 = 0;
                for (; mantSize > 9; mantSize--)
                {
                    char c = At(p); p++;
                    if (c == '.') { c = At(p); p++; }
                    frac1 = 10 * frac1 + (c - '0');
                }
                for (; mantSize > 0; mantSize--)
                {
                    char c = At(p); p++;
                    if (c == '.') { c = At(p); p++; }
                    frac2 = 10 * frac2 + (c - '0');
                }
                fraction = (1.0e9 * frac1) + frac2;
            }

            p = pExp;
            if (At(p) == 'E' || At(p) == 'e')
            {
                p++;
                if (At(p) == '-') { expSign = true; p++; }
                else
                {
                    if (At(p) == '+') p++;
                    expSign = false;
                }
                if (!(At(p) >= '0' && At(p) <= '9'))
                {
                    p = pExp;
                    goto done;
                }
                while (At(p) >= '0' && At(p) <= '9')
                {
                    exp = exp * 10 + (At(p) - '0');
                    p++;
                }
            }
            if (expSign) exp = fracExp - exp;
            else exp = fracExp + exp;

            if (exp < 0) { expSign = true; exp = -exp; }
            else expSign = false;
            if (exp > maxExponent) exp = maxExponent;
            dblExp = 1.0;
            for (int d = 0; exp != 0; exp >>= 1, ++d)
                if ((exp & 1) != 0) dblExp *= powersOf10[d];
            if (expSign) fraction /= dblExp;
            else fraction *= dblExp;

        done:
            end = p;
            return sign ? -fraction : fraction;
        }

        public static bool IsValidInt(this string s)
        {
            int len = s.Length;
            if (len == 0) return false;
            int from = 0;
            if (len != 1 && (s[0] == '+' || s[0] == '-')) from++;
            for (int i = from; i < len; i++) if (!(s[i] >= '0' && s[i] <= '9')) return false;
            return true;
        }

        public static bool IsValidFloat(this string s)
        {
            int len = s.Length;
            if (len == 0) return false;
            int from = 0;
            if (s[0] == '+' || s[0] == '-') from++;
            bool exponentFound = false, periodFound = false, signFound = false, exponentValuesFound = false, numbersFound = false;
            for (int i = from; i < len; i++)
            {
                char c = s[i];
                if (c >= '0' && c <= '9')
                {
                    if (exponentFound) exponentValuesFound = true;
                    else numbersFound = true;
                }
                else if (numbersFound && !exponentFound && (c == 'e' || c == 'E')) exponentFound = true;
                else if (!periodFound && !exponentFound && c == '.') periodFound = true;
                else if ((c == '-' || c == '+') && exponentFound && !exponentValuesFound && !signFound) signFound = true;
                else return false;
            }
            return numbersFound;
        }

        static bool IsHex(char c) => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');

        public static bool IsValidHexNumber(this string s, bool withPrefix = false)
        {
            int len = s.Length;
            if (len == 0) return false;
            int from = 0;
            if (len != 1 && (s[0] == '+' || s[0] == '-')) from++;
            if (withPrefix)
            {
                if (len < 3) return false;
                if (s[from] != '0' || s[from + 1] != 'x') return false;
                from += 2;
            }
            if (from == len) return false;
            for (int i = from; i < len; i++) if (!IsHex(s[i])) return false;
            return true;
        }

        public static long HexToInt(this string s)
        {
            if (s.Length == 0) return 0;
            int i = 0;
            long sign = s[0] == '-' ? -1 : 1;
            if (sign < 0) i++;
            if (s.Length > 2 && i + 1 < s.Length && s[i] == '0' && char.ToLowerInvariant(s[i + 1]) == 'x') i += 2;
            long hex = 0;
            for (; i < s.Length; i++)
            {
                char c = char.ToLowerInvariant(s[i]);
                long d;
                if (c >= '0' && c <= '9') d = c - '0';
                else if (c >= 'a' && c <= 'f') d = c - 'a' + 10;
                else { GD.PushError("Invalid hexadecimal notation character in \"" + s + "\"."); return 0; }
                hex = unchecked(hex * 16 + d);
            }
            return hex * sign;
        }

        public static bool IsNumeric(this string s)
        {
            if (s.Length == 0) return false;
            int st = s[0] == '-' ? 1 : 0;
            bool dot = false;
            for (int i = st; i < s.Length; i++)
            {
                char c = s[i];
                if (c == '.') { if (dot) return false; dot = true; }
                else if (!(c >= '0' && c <= '9')) return false;
            }
            return true;
        }

        // ------------------------------------------------------------------ case
        static bool IsUpper(char c) => char.IsUpper(c);
        static bool IsLower(char c) => char.IsLower(c);
        static bool IsDigit(char c) => c >= '0' && c <= '9';

        static string SeparateCompoundWords(string s)
        {
            if (s.Length == 0) return s;
            var sb = new StringBuilder();
            int start = 0;
            bool prevUpper = IsUpper(s[0]), prevLower = IsLower(s[0]), prevDigit = IsDigit(s[0]);
            for (int i = 1; i < s.Length; i++)
            {
                bool curUpper = IsUpper(s[i]), curLower = IsLower(s[i]), curDigit = IsDigit(s[i]);
                bool nextLower = i + 1 < s.Length && IsLower(s[i + 1]);
                bool a = prevLower && curUpper;
                bool b = (prevUpper || prevDigit) && curUpper && nextLower;
                bool c = prevDigit && curLower && nextLower;
                bool d = (prevUpper || prevLower) && curDigit;
                if (a || b || c || d)
                {
                    sb.Append(s, start, i - start).Append(' ');
                    start = i;
                }
                prevUpper = curUpper; prevLower = curLower; prevDigit = curDigit;
            }
            sb.Append(s, start, s.Length - start);
            for (int i = 0; i < sb.Length; i++)
            {
                char ch = sb[i];
                if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' || ch == '_' || ch == '-' || char.IsWhiteSpace(ch)) sb[i] = ' ';
            }
            return sb.ToString().ToLowerInvariant();
        }

        /// <summary>capitalize(): "snake_case" / "camelCase" -> "Snake Case" / "Camel Case".</summary>
        public static string Capitalize(this string s)
        {
            string words = SeparateCompoundWords(s).StripEdges();
            if (words.Length == 0) return "";
            var parts = words.Split(' ');
            var sb = new StringBuilder();
            for (int i = 0; i < parts.Length; i++)
            {
                string slice = parts[i];
                if (slice.Length == 0) continue;
                if (i > 0) sb.Append(' ');
                sb.Append(char.ToUpperInvariant(slice[0])).Append(slice, 1, slice.Length - 1);
            }
            return sb.ToString();
        }

        public static string ToSnakeCase(this string s) => SeparateCompoundWords(s).Replace(' ', '_');

        public static string ToCamelCase(this string s)
        {
            var parts = SeparateCompoundWords(s).StripEdges().Split(' ');
            var sb = new StringBuilder();
            for (int i = 0; i < parts.Length; i++)
            {
                if (parts[i].Length == 0) continue;
                sb.Append(i == 0 ? char.ToLowerInvariant(parts[i][0]) : char.ToUpperInvariant(parts[i][0])).Append(parts[i], 1, parts[i].Length - 1);
            }
            return sb.ToString();
        }

        public static string ToPascalCase(this string s)
        {
            var parts = SeparateCompoundWords(s).StripEdges().Split(' ');
            var sb = new StringBuilder();
            foreach (var p in parts)
            {
                if (p.Length == 0) continue;
                sb.Append(char.ToUpperInvariant(p[0])).Append(p, 1, p.Length - 1);
            }
            return sb.ToString();
        }

        public static int NocasecmpTo(this string a, string b)
        {
            if (a.Length == 0 && b.Length == 0) return 0;
            if (a.Length == 0) return -1;
            if (b.Length == 0) return 1;
            for (int i = 0; ; i++)
            {
                if (i == a.Length && i == b.Length) return 0;
                if (i == a.Length) return -1;
                if (i == b.Length) return 1;
                char x = char.ToUpperInvariant(a[i]), y = char.ToUpperInvariant(b[i]);
                if (x < y) return -1;
                if (x > y) return 1;
            }
        }

        public static int CasecmpTo(this string a, string b)
        {
            int c = string.CompareOrdinal(a, b);
            return c < 0 ? -1 : c > 0 ? 1 : 0;
        }

        /// <summary>String's `<` (code unit order).</summary>
        public static bool Less(string a, string b) => string.CompareOrdinal(a, b) < 0;

        public static float Similarity(this string a, string b)
        {
            if (a == b) return 1f;
            if (a.Length < 2 || b.Length < 2) return 0f;
            int srcSize = a.Length - 1, tgtSize = b.Length - 1;
            int sum = srcSize + tgtSize, inter = 0;
            for (int i = 0; i < srcSize; i++)
            {
                char i0 = a[i], i1 = a[i + 1];
                for (int j = 0; j < tgtSize; j++)
                    if (i0 == b[j] && i1 == b[j + 1]) { inter++; break; }
            }
            return (2.0f * inter) / sum;
        }

        // ------------------------------------------------------------------ escapes, encodings, hashes
        public static string CEscape(this string s) =>
            s.Replace("\\", "\\\\").Replace("\a", "\\a").Replace("\b", "\\b").Replace("\f", "\\f").Replace("\n", "\\n")
             .Replace("\r", "\\r").Replace("\t", "\\t").Replace("\v", "\\v").Replace("'", "\\'").Replace("\"", "\\\"");

        public static string JsonEscape(this string s) =>
            s.Replace("\\", "\\\\").Replace("\b", "\\b").Replace("\f", "\\f").Replace("\n", "\\n").Replace("\r", "\\r")
             .Replace("\t", "\\t").Replace("\v", "\\v").Replace("\"", "\\\"");

        public static string XmlEscape(this string s, bool quotes = false)
        {
            s = s.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;");
            if (quotes) s = s.Replace("'", "&apos;").Replace("\"", "&quot;");
            return s;
        }

        public static string UriEncode(this string s)
        {
            var bytes = Encoding.UTF8.GetBytes(s);
            var sb = new StringBuilder();
            foreach (byte b in bytes)
            {
                char c = (char)b;
                if (c == '.' || c == '-' || c == '~' || c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))
                    sb.Append(c);
                else sb.Append('%').Append("0123456789ABCDEF"[b >> 4]).Append("0123456789ABCDEF"[b & 15]);
            }
            return sb.ToString();
        }

        public static string UriDecode(this string s)
        {
            var bytes = new List<byte>();
            for (int i = 0; i < s.Length; i++)
            {
                char c = s[i];
                if (c == '%' && i + 2 < s.Length && IsHex(s[i + 1]) && IsHex(s[i + 2]))
                {
                    bytes.Add((byte)Convert.ToInt32(s.Substring(i + 1, 2), 16));
                    i += 2;
                }
                else if (c == '+') bytes.Add((byte)' ');
                else bytes.AddRange(Encoding.UTF8.GetBytes(c.ToString()));
            }
            return Encoding.UTF8.GetString(bytes.ToArray());
        }

        public static byte[] ToUtf8Buffer(this string s) => Encoding.UTF8.GetBytes(s);
        public static byte[] ToAsciiBuffer(this string s)
        {
            var r = new byte[s.Length];
            for (int i = 0; i < s.Length; i++) r[i] = s[i] < 128 ? (byte)s[i] : (byte)'?';
            return r;
        }

        public static string GetStringFromUtf8(this byte[] b) => b == null ? "" : Encoding.UTF8.GetString(b);
        public static string GetStringFromAscii(this byte[] b)
        {
            if (b == null) return "";
            var sb = new StringBuilder(b.Length);
            foreach (var x in b) { if (x == 0) break; sb.Append((char)x); }
            return sb.ToString();
        }

        public static string HexEncode(this byte[] b)
        {
            var sb = new StringBuilder(b.Length * 2);
            foreach (var x in b) sb.Append("0123456789abcdef"[x >> 4]).Append("0123456789abcdef"[x & 15]);
            return sb.ToString();
        }

        public static byte[] HexDecode(this string s)
        {
            var r = new byte[s.Length / 2];
            for (int i = 0; i < r.Length; i++) r[i] = (byte)Convert.ToInt32(s.Substring(i * 2, 2), 16);
            return r;
        }

        public static string Md5Text(this string s) { using (var h = MD5.Create()) return HexEncode(h.ComputeHash(Encoding.UTF8.GetBytes(s))); }
        public static string Sha1Text(this string s) { using (var h = SHA1.Create()) return HexEncode(h.ComputeHash(Encoding.UTF8.GetBytes(s))); }
        public static string Sha256Text(this string s) { using (var h = SHA256.Create()) return HexEncode(h.ComputeHash(Encoding.UTF8.GetBytes(s))); }
        public static byte[] Md5Buffer(this string s) { using (var h = MD5.Create()) return h.ComputeHash(Encoding.UTF8.GetBytes(s)); }
        public static byte[] Sha256Buffer(this string s) { using (var h = SHA256.Create()) return h.ComputeHash(Encoding.UTF8.GetBytes(s)); }

        /// <summary>String.hash() (djb2 over code points; the same as GDScript's hash(some_string)).</summary>
        public static long Hash(this string s) => GHash.Str(s);

        // ------------------------------------------------------------------ paths
        public static string GetFile(this string s)
        {
            int sep = Math.Max(s.LastIndexOf('/'), s.LastIndexOf('\\'));
            return sep == -1 ? s : s.Substring(sep + 1);
        }

        public static string GetExtension(this string s)
        {
            int pos = s.LastIndexOf('.');
            if (pos < 0 || pos < Math.Max(s.LastIndexOf('/'), s.LastIndexOf('\\'))) return "";
            return s.Substring(pos + 1);
        }

        public static string GetBasename(this string s)
        {
            int pos = s.LastIndexOf('.');
            if (pos < 0 || pos < Math.Max(s.LastIndexOf('/'), s.LastIndexOf('\\'))) return s;
            return s.Substring(0, pos);
        }

        public static string GetBaseDir(this string s)
        {
            int end = 0;
            int basepos = s.IndexOf("://", StringComparison.Ordinal);
            if (basepos != -1) end = basepos + 3;
            if (end == 0)
            {
                basepos = s.IndexOf(":/", StringComparison.Ordinal);
                if (basepos == -1) basepos = s.IndexOf(":\\", StringComparison.Ordinal);
                if (basepos != -1) end = basepos + 2;
            }
            if (end == 0 && s.StartsWith("/", StringComparison.Ordinal)) end = 1;
            string rs, b = "";
            if (end != 0) { rs = s.Substring(end); b = s.Substring(0, end); }
            else rs = s;
            int sep = Math.Max(rs.LastIndexOf('/'), rs.LastIndexOf('\\'));
            if (sep == -1) return b;
            return b + rs.Substring(0, sep);
        }

        public static string PathJoin(this string s, string file)
        {
            if (s.Length == 0) return file;
            if (s[s.Length - 1] == '/' || (file.Length > 0 && file[0] == '/')) return s + file;
            return s + "/" + file;
        }

        public static string ValidateFilename(this string s)
        {
            const string invalid = ":/\\?*\"|%<>";
            var sb = new StringBuilder(s.StripEdges());
            for (int i = 0; i < sb.Length; i++) if (invalid.IndexOf(sb[i]) >= 0) sb[i] = '_';
            return sb.ToString();
        }

        /// <summary>format(values, placeholder): "{key}" replaced by str(value) for each key of a dictionary (or index of an array).</summary>
        public static string FormatG(this string s, Var values, string placeholder = "{_}")
        {
            string r = s;
            if (values.IsDict)
            {
                foreach (var kv in values.AsDict().Pairs())
                    r = r.Replace(placeholder.Replace("_", GFormat.Str(kv.Key)), GFormat.Str(kv.Value));
            }
            else if (values.IsArr)
            {
                var a = values.AsArr();
                for (int i = 0; i < a.Size(); i++)
                {
                    var item = a[i];
                    if (item.IsArr && item.AsArr().Size() == 2)
                        r = r.Replace(placeholder.Replace("_", GFormat.Str(item.AsArr()[0])), GFormat.Str(item.AsArr()[1]));
                    else r = r.Replace(placeholder.Replace("_", i.ToString(CultureInfo.InvariantCulture)), GFormat.Str(item));
                }
            }
            return r;
        }

        /// <summary>chr(code).</summary>
        public static string Chr(int code) => char.ConvertFromUtf32(code);
    }
}
