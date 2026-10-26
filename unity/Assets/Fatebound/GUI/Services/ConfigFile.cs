// Fatebound engine services (Unity port): Godot's ConfigFile (core/io/config_file.cpp) -- [section] / key=value text,
// values in Godot's text format (var_to_str / VariantParser, Sim/Script/GMarshal.cs), sections and keys kept in the
// order they were added (a section-less key goes first), so a file saved here is byte-identical to Godot's and either
// reads the other's.
using System;
using System.Collections.Generic;
using System.Text;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public sealed partial class ConfigFile
    {
        sealed class OMap<T>
        {
            public readonly List<string> Keys = new List<string>();
            public readonly Dictionary<string, T> Map = new Dictionary<string, T>();
            public bool Has(string k) => Map.ContainsKey(k);
            public int Count => Keys.Count;

            public void Set(string k, T v, bool front = false)
            {
                if (!Map.ContainsKey(k))
                {
                    if (front) Keys.Insert(0, k);
                    else Keys.Add(k);
                }
                Map[k] = v;
            }

            public void Erase(string k)
            {
                if (Map.Remove(k)) Keys.Remove(k);
            }
        }

        readonly OMap<OMap<Var>> _values = new OMap<OMap<Var>>();

        /// <summary>set_value(section, key, value): null erases the key (and an emptied section).</summary>
        public void SetValue(string section, string key, Var value)
        {
            if (value.IsNil)
            {
                if (!_values.Has(section)) return;
                var s = _values.Map[section];
                s.Erase(key);
                if (s.Count == 0) _values.Erase(section);
                return;
            }
            if (!_values.Has(section)) _values.Set(section, new OMap<Var>(), section.Length == 0);
            _values.Map[section].Set(key, value);
        }

        public Var GetValue(string section, string key, Var defaultValue = default)
        {
            if (!_values.Map.TryGetValue(section, out var s) || !s.Map.TryGetValue(key, out Var v))
            {
                if (defaultValue.IsNil)
                    GD.PushError("Couldn't find the given section \"" + section + "\" and key \"" + key + "\", and no default was given.");
                return defaultValue;
            }
            return v;
        }

        public bool HasSection(string section) => _values.Has(section);
        public bool HasSectionKey(string section, string key) => _values.Map.TryGetValue(section, out var s) && s.Has(key);
        public string[] GetSections() => _values.Keys.ToArray();

        public string[] GetSectionKeys(string section)
        {
            if (!_values.Map.TryGetValue(section, out var s))
            {
                GD.PushError("Cannot get keys from nonexistent section \"" + section + "\".");
                return Array.Empty<string>();
            }
            return s.Keys.ToArray();
        }

        public void EraseSection(string section)
        {
            if (!_values.Has(section)) { GD.PushError("Cannot erase nonexistent section \"" + section + "\"."); return; }
            _values.Erase(section);
        }

        public void EraseSectionKey(string section, string key)
        {
            if (!_values.Map.TryGetValue(section, out var s)) { GD.PushError("Cannot erase key \"" + key + "\" from nonexistent section \"" + section + "\"."); return; }
            if (!s.Has(key)) { GD.PushError("Cannot erase nonexistent key \"" + key + "\" from section \"" + section + "\"."); return; }
            s.Erase(key);
            if (s.Count == 0) _values.Erase(section);
        }

        public void Clear()
        {
            _values.Keys.Clear();
            _values.Map.Clear();
        }

        // ------------------------------------------------------------------ text
        /// <summary>String::property_name_encode: quoted and escaped when it has '=', '"', ';', '[', ']', spaces or non-ASCII.</summary>
        static string PropertyNameEncode(string s)
        {
            foreach (char c in s)
                if (c == '=' || c == '"' || c == ';' || c == '[' || c == ']' || c < 33 || c > 126)
                    return "\"" + GMarshal.CEscapeMultiline(s) + "\"";
            return s;
        }

        string Encode(bool escapeSectionBracket)
        {
            var sb = new StringBuilder();
            bool first = true;
            foreach (var sec in _values.Keys)
            {
                if (first) first = false;
                else sb.Append('\n');
                if (sec.Length > 0) sb.Append('[').Append(escapeSectionBracket ? sec.Replace("]", "\\]") : sec).Append("]\n\n");
                var s = _values.Map[sec];
                foreach (var k in s.Keys) sb.Append(PropertyNameEncode(k)).Append('=').Append(GMarshal.VarToStr(s.Map[k])).Append('\n');
            }
            return sb.ToString();
        }

        /// <summary>encode_to_text(): the file's text.</summary>
        public string EncodeToText() => Encode(false);

        public int Save(string path)
        {
            var f = FileAccess.Open(path, FileAccess.WRITE);
            if (f == null) return FileAccess.GetOpenError();
            using (f) f.StoreString(Encode(true));
            return GD.OK;
        }

        /// <summary>load(path): adds the file's values (OK, the open error, or ERR_PARSE_ERROR...).</summary>
        public int Load(string path)
        {
            var f = FileAccess.Open(path, FileAccess.READ);
            if (f == null) return FileAccess.GetOpenError();
            string text;
            using (f) text = f.GetAsText();
            return ParseText(path, text);
        }

        public int Parse(string data) => ParseText("<string>", data ?? "");

        int ParseText(string path, string text)
        {
            var p = new GVariantParser(text);
            int lines = 0;
            string section = "";
            while (true)
            {
                int e = p.ParseTagAssignEof(ref lines, out string err, out string tag, out string assign, out Var value);
                if (e == GD.ERR_FILE_EOF) return GD.OK;
                if (e != GD.OK)
                {
                    GD.PushError("ConfigFile parse error at " + path + ":" + lines + ": " + err + ".");
                    return e;
                }
                if (assign.Length > 0) SetValue(section, assign, value);
                else if (!string.IsNullOrEmpty(tag)) section = tag.Replace("\\]", "]");
            }
        }

        public int LoadEncrypted(string path, byte[] key) => GD.ERR_UNAVAILABLE;
        public int LoadEncryptedPass(string path, string password) => GD.ERR_UNAVAILABLE;
        public int SaveEncrypted(string path, byte[] key) => GD.ERR_UNAVAILABLE;
        public int SaveEncryptedPass(string path, string password) => GD.ERR_UNAVAILABLE;
    }
}
