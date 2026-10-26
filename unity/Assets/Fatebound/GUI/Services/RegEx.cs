// Fatebound engine services (Unity port): Godot's RegEx / RegExMatch (modules/regex, PCRE2) over
// System.Text.RegularExpressions. The patterns the game writes (groups, named groups, look-arounds, classes) mean the
// same in both; sub()'s replacement uses PCRE2's syntax ($1, ${1}, $name, ${name}, $$), translated here. One known
// difference: PCRE2 as Godot compiles it has ASCII-only \w \d \s, .NET's are Unicode.
using System;
using System.Collections.Generic;
using System.Text;
using System.Text.RegularExpressions;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public sealed partial class RegExMatch
    {
        internal string subject = "";
        internal int[] starts = Array.Empty<int>(), ends = Array.Empty<int>();
        internal readonly GDict names = new GDict();

        public string Subject => subject;
        public GDict Names => names;
        public string[] Strings => GetStrings();

        public string GetSubject() => subject;
        public int GetGroupCount() => starts.Length == 0 ? 0 : starts.Length - 1;
        /// <summary>{group name: group index} for the named groups that matched.</summary>
        public GDict GetNames() => names;

        public string[] GetStrings()
        {
            var r = new string[starts.Length];
            for (int i = 0; i < r.Length; i++) r[i] = starts[i] < 0 ? "" : subject.Substring(starts[i], ends[i] - starts[i]);
            return r;
        }

        int Find(int i) => i >= starts.Length ? -1 : i;
        int Find(string name) => names.TryGetValue(name, out Var v) ? v.AsInt() : -1;

        string Str(int id) => id < 0 || starts[id] < 0 ? "" : subject.Substring(starts[id], ends[id] - starts[id]);

        public string GetString(int group = 0) => Str(Find(group));
        public string GetString(string name) => Str(Find(name));
        public int GetStart(int group = 0) { int id = Find(group); return id < 0 ? -1 : starts[id]; }
        public int GetStart(string name) { int id = Find(name); return id < 0 ? -1 : starts[id]; }
        public int GetEnd(int group = 0) { int id = Find(group); return id < 0 ? -1 : ends[id]; }
        public int GetEnd(string name) { int id = Find(name); return id < 0 ? -1 : ends[id]; }
    }

    public sealed partial class RegEx
    {
        Regex _re;
        string _pattern = "";

        public static RegEx CreateFromString(string pattern, bool showError = true)
        {
            var r = new RegEx();
            r.Compile(pattern, showError);
            return r;
        }

        /// <summary>compile(pattern): OK, or FAILED (with the reason printed) for a bad pattern.</summary>
        public int Compile(string pattern, bool showError = true)
        {
            Clear();
            _pattern = pattern ?? "";
            try
            {
                _re = new Regex(_pattern, RegexOptions.CultureInvariant);
                return GD.OK;
            }
            catch (ArgumentException e)
            {
                if (showError) GD.PushError("RegEx compilation error: " + e.Message);
                _re = null;
                return GD.FAILED;
            }
        }

        public void Clear() { _re = null; _pattern = ""; }
        public bool IsValid() => _re != null;
        public string GetPattern() => _pattern;
        public int GetGroupCount() => _re == null ? 0 : _re.GetGroupNumbers().Length - 1;

        public string[] GetNames()
        {
            if (_re == null) return Array.Empty<string>();
            // (PCRE2's name table: sorted by name)
            var r = new List<string>();
            foreach (var n in _re.GetGroupNames()) if (!int.TryParse(n, out _)) r.Add(n);
            r.Sort(string.CompareOrdinal);
            return r.ToArray();
        }

        RegExMatch Wrap(Match m, string subject)
        {
            int n = _re.GetGroupNumbers().Length;
            var r = new RegExMatch { subject = subject, starts = new int[n], ends = new int[n] };
            for (int i = 0; i < n; i++)
            {
                var g = m.Groups[i];
                r.starts[i] = g.Success ? g.Index : -1;
                r.ends[i] = g.Success ? g.Index + g.Length : -1;
            }
            foreach (var name in GetNames())
            {
                var g = m.Groups[name];
                if (g.Success) r.names[name] = _re.GroupNumberFromName(name);
            }
            return r;
        }

        bool Ready(int offset, string what)
        {
            if (_re == null) { GD.PushError("Condition \"!is_valid()\" is true."); return false; }
            if (offset < 0) { GD.PushError("RegEx " + what + " offset must be >= 0"); return false; }
            return true;
        }

        static string Limit(string s, int end) => end >= 0 && end < s.Length ? s.Substring(0, end) : s;

        /// <summary>search(subject, offset, end): the first match at or after offset (within subject[0, end)), or null.</summary>
        public RegExMatch Search(string subject, int offset = 0, int end = -1)
        {
            if (!Ready(offset, "search")) return null;
            string s = Limit(subject ?? "", end);
            if (offset > s.Length) return null;
            var m = _re.Match(s, offset);
            return m.Success ? Wrap(m, subject ?? "") : null;
        }

        public GArray SearchAll(string subject, int offset = 0, int end = -1)
        {
            var r = new GArray();
            if (!Ready(offset, "search_all")) return r;
            string s = Limit(subject ?? "", end);
            if (offset > s.Length) return r;
            for (var m = _re.Match(s, offset); m.Success; m = m.NextMatch()) r.Append(Var.Of(Wrap(m, subject ?? "")));
            return r;
        }

        /// <summary>sub(subject, replacement, all, offset, end): the subject with the first (or every) match in
        /// [offset, end) replaced.</summary>
        public string Sub(string subject, string replacement, bool all = false, int offset = 0, int end = -1)
        {
            if (!Ready(offset, "sub")) return "";
            subject = subject ?? "";
            string s = Limit(subject, end);
            if (offset > s.Length) { GD.PushError("PCRE2 Error: bad offset value"); return ""; }
            string rep = Translate(replacement ?? "");
            return _re.Replace(s, rep, all ? -1 : 1, offset) + subject.Substring(s.Length);
        }

        /// <summary>A PCRE2 replacement string in .NET's syntax.</summary>
        static string Translate(string r)
        {
            var sb = new StringBuilder();
            for (int i = 0; i < r.Length; i++)
            {
                char c = r[i];
                if (c != '$') { sb.Append(c); continue; }
                if (i + 1 >= r.Length) { sb.Append("$$"); continue; }
                char n = r[i + 1];
                if (n == '$') { sb.Append("$$"); i++; }
                else if (n == '{')
                {
                    int close = r.IndexOf('}', i + 2);
                    if (close < 0) { sb.Append("$$"); continue; }
                    sb.Append("${").Append(r, i + 2, close - i - 2).Append('}');
                    i = close;
                }
                else if (char.IsDigit(n))
                {
                    int j = i + 1;
                    while (j < r.Length && char.IsDigit(r[j])) j++;
                    sb.Append("${").Append(r, i + 1, j - i - 1).Append('}');
                    i = j - 1;
                }
                else if (char.IsLetter(n) || n == '_')
                {
                    int j = i + 1;
                    while (j < r.Length && (char.IsLetterOrDigit(r[j]) || r[j] == '_')) j++;
                    sb.Append("${").Append(r, i + 1, j - i - 1).Append('}');
                    i = j - 1;
                }
                else sb.Append("$$");
            }
            return sb.ToString();
        }
    }
}
