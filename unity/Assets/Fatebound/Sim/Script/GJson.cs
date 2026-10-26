// Godot's JSON (core/io/json.cpp): stringify with sorted keys by default and floats as Godot writes them ("5.0",
// 14 significant digits), parse with every number a float (Godot's own strtod). Saves written by the Godot build
// read back here unchanged and the other way round; the server (Godot) and this client agree on every message.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Text;

namespace Fatebound.Sim
{
    public sealed class JSON
    {
        public Var data;
        string _errorMessage = "";
        int _errorLine;
        string _text = "";

        /// <summary>JSON.stringify(data, indent, sort_keys, full_precision).</summary>
        public static string Stringify(Var v, string indent = "", bool sortKeys = true, bool fullPrecision = false)
        {
            var sb = new StringBuilder();
            var markers = new HashSet<object>();
            DoStringify(sb, v, indent, 0, sortKeys, markers, fullPrecision);
            return sb.ToString();
        }

        /// <summary>JSON.parse_string(text): the value, or Nil (with an error printed) when it doesn't parse.</summary>
        public static Var ParseString(string text)
        {
            var j = new JSON();
            if (j.Parse(text) != GD.OK)
            {
                GD.PushError("Parse JSON failed. Error at line " + j._errorLine + ": " + j._errorMessage);
                return Var.Nil;
            }
            return j.data;
        }

        /// <summary>json.parse(text): OK or ERR_PARSE_ERROR (then get_error_line / get_error_message).</summary>
        public int Parse(string text, bool keepText = false)
        {
            if (keepText) _text = text;
            int idx = 0, line = 0;
            string err = "";
            text = text ?? "";
            var r = DoParse(text, ref idx, ref line, ref err, out var value);
            _errorLine = line;
            _errorMessage = err;
            if (r == GD.OK) data = value;
            return r;
        }

        public Var GetData() => data;
        public int GetErrorLine() => _errorLine;
        public string GetErrorMessage() => _errorMessage;
        public string GetParsedText() => _text;

        // ------------------------------------------------------------------ stringify
        static void AddIndent(StringBuilder sb, string indent, int n)
        {
            for (int i = 0; i < n; i++) sb.Append(indent);
        }

        static void DoStringify(StringBuilder r, Var v, string indent, int cur, bool sortKeys, HashSet<object> markers, bool fullPrecision)
        {
            if (cur > 1024) { r.Append("..."); GD.PushError("JSON structure is too deep. Bailing."); return; }
            string colon = indent.Length == 0 ? ":" : ": ";
            string endStatement = indent.Length == 0 ? "" : "\n";
            switch (v.Type)
            {
                case VT.Nil: r.Append("null"); return;
                case VT.Bool: r.Append(v.Truthy ? "true" : "false"); return;
                case VT.Int: r.Append(GFormat.Itos(v.AsLong())); return;
                case VT.Float:
                    {
                        double num = v.AsFloat();
                        if (double.IsNaN(num) || double.IsInfinity(num))
                        {
                            if (double.IsPositiveInfinity(num)) r.Append("1e99999");
                            else if (double.IsNegativeInfinity(num)) r.Append("-1e99999");
                            else r.Append("null");
                            return;
                        }
                        if (num == 0.0) { r.Append("0.0"); return; }
                        if (fullPrecision)
                        {
                            string sci = GFormat.NumScientific(num);
                            r.Append(sci);
                            if (sci.IndexOf('.') < 0 && sci.IndexOf('e') < 0) r.Append(".0");
                        }
                        else
                        {
                            double magnitude = Math.Log10(Math.Abs(num));
                            int precision = Math.Max(1, 14 - (int)Math.Floor(magnitude));
                            r.Append(GFormat.Num(num, precision));
                        }
                        return;
                    }
                case VT.Arr:
                    WriteList(r, v.AsArr(), v.AsArr().List, indent, cur, sortKeys, markers, fullPrecision, endStatement);
                    return;
                case VT.Dict:
                    {
                        var d = v.AsDict();
                        if (markers.Contains(d)) { r.Append("\"{...}\""); GD.PushError("Converting circular structure to JSON."); return; }
                        if (d.IsEmpty()) { r.Append("{}"); return; }
                        r.Append('{').Append(endStatement);
                        markers.Add(d);
                        var keys = d.Keys().List;
                        if (sortKeys) GSort.Sort(keys, StringLikeLess);
                        bool first = true;
                        foreach (var key in keys)
                        {
                            if (!first) r.Append(',').Append(endStatement);
                            first = false;
                            AddIndent(r, indent, cur + 1);
                            DoStringify(r, GFormat.Str(key), indent, cur + 1, sortKeys, markers, fullPrecision);
                            r.Append(colon);
                            DoStringify(r, d[key], indent, cur + 1, sortKeys, markers, fullPrecision);
                        }
                        r.Append(endStatement);
                        AddIndent(r, indent, cur);
                        r.Append('}');
                        markers.Remove(d);
                        return;
                    }
            }
            if (v.Type == VT.Obj && v.Obj is IList list && !(v.Obj is string))
            {
                var tmp = new List<Var>(list.Count);
                foreach (var x in list) tmp.Add(Var.Of(x));
                WriteList(r, list, tmp, indent, cur, sortKeys, markers, fullPrecision, endStatement);
                return;
            }
            r.Append('"').Append(GStr.JsonEscape(GFormat.Str(v))).Append('"');
        }

        static void WriteList(StringBuilder r, object id, List<Var> items, string indent, int cur, bool sortKeys, HashSet<object> markers, bool fullPrecision, string endStatement)
        {
            if (markers.Contains(id)) { r.Append("\"[...]\""); GD.PushError("Converting circular structure to JSON."); return; }
            if (items.Count == 0) { r.Append("[]"); return; }
            r.Append('[').Append(endStatement);
            markers.Add(id);
            bool first = true;
            foreach (var x in items)
            {
                if (!first) r.Append(',').Append(endStatement);
                first = false;
                AddIndent(r, indent, cur + 1);
                DoStringify(r, x, indent, cur + 1, sortKeys, markers, fullPrecision);
            }
            r.Append(endStatement);
            AddIndent(r, indent, cur);
            r.Append(']');
            markers.Remove(id);
        }

        /// <summary>StringLikeVariantOrder: strings by their text, anything else by Variant::operator< (the type's
        /// number first -- int keys before float keys before strings -- then `<`).</summary>
        static bool StringLikeLess(Var a, Var b)
        {
            if (a.IsString && b.IsString) return GStr.Less(a.AsString(), b.AsString());
            int ta = a.GodotType, tb = b.GodotType;
            if (ta != tb) return ta < tb;
            return Var.Less(a, b);
        }

        // ------------------------------------------------------------------ parse
        enum Tk { CurlyOpen, CurlyClose, BracketOpen, BracketClose, Identifier, String, Number, Colon, Comma, Eof }

        struct Token { public Tk type; public Var value; }

        static readonly string[] TkName = { "'{'", "'}'", "'['", "']'", "identifier", "string", "number", "':'", "','", "EOF" };

        static int GetToken(string s, ref int index, ref Token tok, ref int line, ref string err)
        {
            int len = s.Length;
            while (true)
            {
                if (index >= len) { tok.type = Tk.Eof; return GD.OK; }
                char c = s[index];
                switch (c)
                {
                    case '\n': line++; index++; break;
                    case '{': tok.type = Tk.CurlyOpen; index++; return GD.OK;
                    case '}': tok.type = Tk.CurlyClose; index++; return GD.OK;
                    case '[': tok.type = Tk.BracketOpen; index++; return GD.OK;
                    case ']': tok.type = Tk.BracketClose; index++; return GD.OK;
                    case ':': tok.type = Tk.Colon; index++; return GD.OK;
                    case ',': tok.type = Tk.Comma; index++; return GD.OK;
                    case '"':
                        {
                            index++;
                            var str = new StringBuilder();
                            while (true)
                            {
                                if (index >= len) { err = "Unterminated string"; return GD.ERR_PARSE_ERROR; }
                                char ch = s[index];
                                if (ch == '"') { index++; break; }
                                if (ch == '\\')
                                {
                                    index++;
                                    if (index >= len) { err = "Unterminated string"; return GD.ERR_PARSE_ERROR; }
                                    char next = s[index];
                                    int res;
                                    switch (next)
                                    {
                                        case 'b': res = 8; break;
                                        case 't': res = 9; break;
                                        case 'n': res = 10; break;
                                        case 'f': res = 12; break;
                                        case 'r': res = 13; break;
                                        case 'u':
                                            {
                                                if (!Hex4(s, index + 1, out res, ref err)) return GD.ERR_PARSE_ERROR;
                                                index += 4;
                                                if ((res & 0xfffffc00) == 0xd800)
                                                {
                                                    if (index + 2 >= len || s[index + 1] != '\\' || s[index + 2] != 'u')
                                                    {
                                                        err = "Invalid UTF-16 sequence in string, unpaired lead surrogate";
                                                        return GD.ERR_PARSE_ERROR;
                                                    }
                                                    index += 2;
                                                    if (!Hex4(s, index + 1, out int trail, ref err)) return GD.ERR_PARSE_ERROR;
                                                    if ((trail & 0xfffffc00) == 0xdc00)
                                                    {
                                                        res = (res << 10) + trail - ((0xd800 << 10) + 0xdc00 - 0x10000);
                                                        index += 4;
                                                    }
                                                    else
                                                    {
                                                        err = "Invalid UTF-16 sequence in string, unpaired lead surrogate";
                                                        return GD.ERR_PARSE_ERROR;
                                                    }
                                                }
                                                else if ((res & 0xfffffc00) == 0xdc00)
                                                {
                                                    err = "Invalid UTF-16 sequence in string, unpaired trail surrogate";
                                                    return GD.ERR_PARSE_ERROR;
                                                }
                                                break;
                                            }
                                        case '"':
                                        case '\\':
                                        case '/': res = next; break;
                                        default: err = "Invalid escape sequence"; return GD.ERR_PARSE_ERROR;
                                    }
                                    if (res > 0xFFFF) str.Append(char.ConvertFromUtf32(res));
                                    else str.Append((char)res);
                                }
                                else
                                {
                                    if (ch == '\n') line++;
                                    str.Append(ch);
                                }
                                index++;
                            }
                            tok.type = Tk.String;
                            tok.value = str.ToString();
                            return GD.OK;
                        }
                    default:
                        {
                            if (c <= 32) { index++; break; }
                            if (c == '-' || (c >= '0' && c <= '9'))
                            {
                                double number = GStr.Strtod(s, index, out int end);
                                index = end;
                                tok.type = Tk.Number;
                                tok.value = number;
                                return GD.OK;
                            }
                            if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'))
                            {
                                int st = index;
                                while (index < len && ((s[index] >= 'a' && s[index] <= 'z') || (s[index] >= 'A' && s[index] <= 'Z'))) index++;
                                tok.type = Tk.Identifier;
                                tok.value = s.Substring(st, index - st);
                                return GD.OK;
                            }
                            err = "Unexpected character";
                            return GD.ERR_PARSE_ERROR;
                        }
                }
            }
        }

        static bool Hex4(string s, int at, out int v, ref string err)
        {
            v = 0;
            for (int j = 0; j < 4; j++)
            {
                if (at + j >= s.Length) { err = "Unterminated string"; return false; }
                char c = s[at + j];
                int d;
                if (c >= '0' && c <= '9') d = c - '0';
                else if (c >= 'a' && c <= 'f') d = c - 'a' + 10;
                else if (c >= 'A' && c <= 'F') d = c - 'A' + 10;
                else { err = "Malformed hex constant in string"; return false; }
                v = (v << 4) | d;
            }
            return true;
        }

        static int ParseValue(out Var value, Token tok, string s, ref int index, ref int line, int depth, ref string err)
        {
            value = Var.Nil;
            if (depth > 1024) { err = "JSON structure is too deep"; return GD.ERR_OUT_OF_MEMORY; }
            switch (tok.type)
            {
                case Tk.CurlyOpen:
                    {
                        var d = new GDict();
                        int e = ParseObject(d, s, ref index, ref line, depth + 1, ref err);
                        if (e != GD.OK) return e;
                        value = d;
                        return GD.OK;
                    }
                case Tk.BracketOpen:
                    {
                        var a = new GArray();
                        int e = ParseArray(a, s, ref index, ref line, depth + 1, ref err);
                        if (e != GD.OK) return e;
                        value = a;
                        return GD.OK;
                    }
                case Tk.Identifier:
                    {
                        string id = tok.value.AsString();
                        if (id == "true") value = true;
                        else if (id == "false") value = false;
                        else if (id == "null") value = Var.Nil;
                        else { err = "Expected 'true', 'false', or 'null', got '" + id + "'"; return GD.ERR_PARSE_ERROR; }
                        return GD.OK;
                    }
                case Tk.Number:
                case Tk.String:
                    value = tok.value;
                    return GD.OK;
            }
            err = "Expected value, got " + TkName[(int)tok.type] + ".";
            return GD.ERR_PARSE_ERROR;
        }

        static int ParseArray(GArray array, string s, ref int index, ref int line, int depth, ref string err)
        {
            var tok = new Token();
            bool needComma = false;
            while (index < s.Length)
            {
                int e = GetToken(s, ref index, ref tok, ref line, ref err);
                if (e != GD.OK) return e;
                if (tok.type == Tk.BracketClose) return GD.OK;
                if (needComma)
                {
                    if (tok.type != Tk.Comma) { err = "Expected ','"; return GD.ERR_PARSE_ERROR; }
                    needComma = false;
                    continue;
                }
                e = ParseValue(out var v, tok, s, ref index, ref line, depth, ref err);
                if (e != GD.OK) return e;
                array.Append(v);
                needComma = true;
            }
            err = "Expected ']'";
            return GD.ERR_PARSE_ERROR;
        }

        static int ParseObject(GDict obj, string s, ref int index, ref int line, int depth, ref string err)
        {
            bool atKey = true;
            string key = "";
            var tok = new Token();
            bool needComma = false;
            while (index < s.Length)
            {
                if (atKey)
                {
                    int e = GetToken(s, ref index, ref tok, ref line, ref err);
                    if (e != GD.OK) return e;
                    if (tok.type == Tk.CurlyClose) return GD.OK;
                    if (needComma)
                    {
                        if (tok.type != Tk.Comma) { err = "Expected '}' or ','"; return GD.ERR_PARSE_ERROR; }
                        needComma = false;
                        continue;
                    }
                    if (tok.type != Tk.String) { err = "Expected key"; return GD.ERR_PARSE_ERROR; }
                    key = tok.value.AsString();
                    e = GetToken(s, ref index, ref tok, ref line, ref err);
                    if (e != GD.OK) return e;
                    if (tok.type != Tk.Colon) { err = "Expected ':'"; return GD.ERR_PARSE_ERROR; }
                    atKey = false;
                }
                else
                {
                    int e = GetToken(s, ref index, ref tok, ref line, ref err);
                    if (e != GD.OK) return e;
                    e = ParseValue(out var v, tok, s, ref index, ref line, depth, ref err);
                    if (e != GD.OK) return e;
                    obj[key] = v;
                    needComma = true;
                    atKey = true;
                }
            }
            err = "Expected '}'";
            return GD.ERR_PARSE_ERROR;
        }

        static int DoParse(string s, ref int index, ref int line, ref string err, out Var value)
        {
            value = Var.Nil;
            var tok = new Token();
            int e = GetToken(s, ref index, ref tok, ref line, ref err);
            if (e != GD.OK) return e;
            e = ParseValue(out value, tok, s, ref index, ref line, 0, ref err);
            if (e != GD.OK) return e;
            // trailing content after the value (whitespace aside) is an error
            e = GetToken(s, ref index, ref tok, ref line, ref err);
            if (e != GD.OK) return e;
            if (tok.type != Tk.Eof)
            {
                err = "Expected 'EOF'";
                return GD.ERR_PARSE_ERROR;
            }
            return GD.OK;
        }
    }
}
