// Builds a UI JSON spec (tools/parity/ui/*.json) with the C# framework -- the same spec godot_ui.gd builds with
// Godot -- runs a few frames and prints every control's global rect; `uiparity` diffs it against Godot's output.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using Fatebound.GUI;
using Fatebound.Sim;

namespace GuiTest
{
    public static class UiParity
    {
        static readonly Assembly GuiAsm = typeof(Control).Assembly;

        static object Val(JsonElement e)
        {
            switch (e.ValueKind)
            {
                case JsonValueKind.String:
                {
                    string s = e.GetString();
                    if (s.StartsWith("#")) return Col.Html(s);
                    if (s.StartsWith("res://")) return ResourceLoader.Load(s);
                    return s;
                }
                case JsonValueKind.Number: return e.TryGetInt64(out long l) && !e.GetRawText().Contains('.') ? (object)(int)l : e.GetDouble();
                case JsonValueKind.True: return true;
                case JsonValueKind.False: return false;
                case JsonValueKind.Array:
                {
                    var a = e.EnumerateArray().ToArray();
                    if (a.Length == 2 && a.All(x => x.ValueKind == JsonValueKind.Number)) return new Vec2(a[0].GetDouble(), a[1].GetDouble());
                    if (a.Length == 4 && a.All(x => x.ValueKind == JsonValueKind.Number)) return new Col(a[0].GetDouble(), a[1].GetDouble(), a[2].GetDouble(), a[3].GetDouble());
                    return a.Select(Val).ToArray();
                }
                case JsonValueKind.Object:
                    if (e.TryGetProperty("type", out _)) return BuildRes(e);
                    return null;
            }
            return null;
        }

        static Type TypeOf(string name)
        {
            var t = GuiAsm.GetTypes().FirstOrDefault(x => x.Name == name && !x.IsNested);
            if (t == null) throw new Exception("no type " + name);
            return t;
        }

        static void Call(object target, string method, object[] args)
        {
            string pascal = PropertyPath.Pascal(method);
            var ms = target.GetType().GetMethods(BindingFlags.Instance | BindingFlags.Public).Where(m => m.Name == pascal && m.GetParameters().Length >= args.Length).ToArray();
            if (ms.Length == 0) throw new Exception("no method " + pascal + " on " + target.GetType().Name);
            var mi = ms.OrderBy(m => m.GetParameters().Length).First();
            var ps = mi.GetParameters();
            var call = new object[ps.Length];
            for (int i = 0; i < ps.Length; i++)
                call[i] = i < args.Length ? ConvertArg(args[i], ps[i].ParameterType) : ps[i].DefaultValue;
            mi.Invoke(target, call);
        }

        static object ConvertArg(object v, Type t)
        {
            if (v == null) return null;
            if (t.IsInstanceOfType(v)) return v;
            if (t.IsEnum) return Enum.ToObject(t, Convert.ToInt64(v));
            if (t == typeof(double)) return Convert.ToDouble(v);
            if (t == typeof(float)) return Convert.ToSingle(v);
            if (t == typeof(int)) return Convert.ToInt32(v);
            if (t == typeof(bool)) return Convert.ToBoolean(v);
            if (Nullable.GetUnderlyingType(t) is Type nt) return ConvertArg(v, nt);
            return v;
        }

        static object BuildRes(JsonElement d)
        {
            var r = Activator.CreateInstance(TypeOf(d.GetProperty("type").GetString()));
            foreach (var p in d.EnumerateObject())
            {
                if (p.Name == "type") continue;
                if (p.Name == "call")
                {
                    foreach (var c in p.Value.EnumerateArray())
                    {
                        var arr = c.EnumerateArray().ToArray();
                        Call(r, arr[0].GetString(), arr.Skip(1).Select(Val).ToArray());
                    }
                    continue;
                }
                PropertyPath.Set(r, p.Name, Val(p.Value));
            }
            return r;
        }

        static Node Build(JsonElement d)
        {
            var n = (Node)Activator.CreateInstance(TypeOf(d.GetProperty("type").GetString()));
            n.Name = d.TryGetProperty("name", out var nm) ? nm.GetString() : "@" + n.GetType().Name;
            if (d.TryGetProperty("props", out var props))
                foreach (var p in props.EnumerateObject()) PropertyPath.Set(n, p.Name, Val(p.Value));
            if (d.TryGetProperty("theme", out var theme) && n is Control c)
                foreach (var kind in theme.EnumerateObject())
                    foreach (var item in kind.Value.EnumerateObject())
                    {
                        var v = Val(item.Value);
                        switch (kind.Name)
                        {
                            case "constant": c.AddThemeConstantOverride(item.Name, Convert.ToInt32(v)); break;
                            case "color": c.AddThemeColorOverride(item.Name, (Col)v); break;
                            case "font": c.AddThemeFontOverride(item.Name, (Font)v); break;
                            case "font_size": c.AddThemeFontSizeOverride(item.Name, Convert.ToInt32(v)); break;
                            case "stylebox": c.AddThemeStyleboxOverride(item.Name, (StyleBox)v); break;
                            case "icon": c.AddThemeIconOverride(item.Name, (Texture2D)v); break;
                        }
                    }
            if (d.TryGetProperty("children", out var ch))
                foreach (var cd in ch.EnumerateArray()) n.AddChild(Build(cd));
            if (d.TryGetProperty("call", out var calls))
                foreach (var cl in calls.EnumerateArray())
                {
                    var arr = cl.EnumerateArray().ToArray();
                    Call(n, arr[0].GetString(), arr.Skip(1).Select(Val).ToArray());
                }
            return n;
        }

        public static void Dump(Node n, string path, List<string> o)
        {
            if (n is Control c)
            {
                var r = c.GetGlobalRect();
                var m = c.GetCombinedMinimumSize();
                o.Add(string.Format(CultureInfo.InvariantCulture, "R {0} {1:F2} {2:F2} {3:F2} {4:F2} min={5:F2},{6:F2}", path, r.position.x, r.position.y, r.size.x, r.size.y, m.x, m.y));
            }
            var kids = n.GetChildren();
            for (int i = 0; i < kids.Count; i++) Dump(kids[i], path + "/" + (kids[i].Name.StartsWith("@") ? i.ToString() : kids[i].Name), o);
        }

        public static (SceneTree tree, int frames) Load(string specPath)
        {
            var doc = JsonDocument.Parse(File.ReadAllText(specPath)).RootElement;
            Vec2 size = new Vec2(760, 420);
            if (doc.TryGetProperty("size", out var sz)) size = new Vec2(sz[0].GetDouble(), sz[1].GetDouble());
            var tree = new SceneTree(size);
            var frame = new Control { Name = "frame" };
            tree.Root.AddChild(frame);
            frame.Size = size;
            frame.AddChild(Build(doc.GetProperty("root")));
            int frames = doc.TryGetProperty("frames", out var fr) ? fr.GetInt32() : 4;
            return (tree, frames);
        }

        public static List<string> Run(string specPath)
        {
            var (tree, frames) = Load(specPath);
            for (int i = 0; i < frames; i++) tree.Iterate(1.0 / 60.0);
            var o = new List<string>();
            foreach (var ch in tree.Root.GetChild(0).GetChildren()) Dump(ch, ch.Name, o);
            return o;
        }
    }
}
