// `guitest runtime`: the C# runtime (Sim/Script) printing the same cases as tools/parity/godot_runtime.gd, line for
// line -- tools/parity/runtime.sh diffs the two. Written the way ported game code uses the runtime.
using System;
using System.Collections.Generic;
using Fatebound.Sim;

namespace GuiTest
{
    public static class RuntimeTest
    {
        static void p(string k, Var v) => Console.WriteLine(k + "|" + GD.Str(v));

        public static void Run()
        {
            var floats = new double[] { 0.0, 0.0 /* (-0.0 in the .gd folds to +0.0) */, 1.0, 0.1, 0.5, 1.0 / 3.0, 2.0 / 3.0, 1e15, 1e16, 123456.789, 1e-5, 1.5e-7, 3.14159265358979,
                100.0 / 7.0, -2.5, 1e20, 1.7976931348623157e308, 0.0 /* (5e-324: Godot's parser reads 0) */, 0.1 + 0.2, Math.Pow(2.0, -15), 12345678.9, 99.995, 0.125, 2.5,
                -1234.5678, 7e-10, 65536.0 * 65536.0 * 65536.0, 0.000123456789, 9.87654321e12 };
            for (int i = 0; i < floats.Length; i++)
            {
                double f = floats[i];
                p(GD.Fmt("str%d", i), f);
                p(GD.Fmt("f%d", i), GD.Fmt("%f", f));
                p(GD.Fmt("f1_%d", i), GD.Fmt("%.1f", f));
                p(GD.Fmt("f2_%d", i), GD.Fmt("%.2f", f));
                p(GD.Fmt("f3_%d", i), GD.Fmt("%.3f", f));
                p(GD.Fmt("f0_%d", i), GD.Fmt("%.0f", f));
                p(GD.Fmt("f5w_%d", i), GD.Fmt("%8.3f|", f));
                p(GD.Fmt("d%d", i), GD.Fmt("%d", f));
                p(GD.Fmt("s%d", i), GD.Fmt("%s", f));
                p(GD.Fmt("json%d", i), JSON.Stringify(f));
                p(GD.Fmt("hash%d", i), GD.Hash(f));
                p(GD.Fmt("v2_%d", i), new Vec2(f, -f));
            }
            var ints = new long[] { 0, 1, -1, 7, -7, 255, 65535, 1000000, -2147483648, 9223372036854775807 };
            for (int i = 0; i < ints.Length; i++)
            {
                long n = ints[i];
                p(GD.Fmt("i%d", i), n);
                p(GD.Fmt("id%d", i), GD.Fmt("%05d|%-6d|%+d|%x|%X|%o|%3d", n, n, n, n, n, n, n));
                p(GD.Fmt("ih%d", i), GD.Hash(n));
                p(GD.Fmt("ij%d", i), JSON.Stringify(n));
            }
            p("vec2", new Vec2(0.1, 2));
            p("vec3", new Vec3(1.5, -0.25, 1e7));
            p("vec2i", new Vec2i(3, -4));
            p("fmtv", GD.Fmt("%.2v", new Vec2(1.234, -5.5)));
            p("fmtc", GD.Fmt("%c%c", 65, "z"));
            p("fmts", GD.Fmt("[%10s][%-10s][%s]", "ab", "cd", GArray.Of(1, "x")));
            p("fmtstar", GD.Fmt("%*d|%.*f", 6, 42, 2, 3.14159));
            p("fmtpct", "100%%");
            var d = new GDict { { "a", 1 }, { "b", GArray.Of(1, 2.5, "x", Var.Nil, true) }, { "c", new GDict { { "d", new Vec2(1, 2) }, { "e", "q\"uote\n" } } }, { 5, "five" }, { 2.5, "f" } };
            p("strd", d);
            p("jsond", JSON.Stringify(d));
            p("jsondi", JSON.Stringify(d, "\t").Replace("\n", "\\n").Replace("\t", "\\t"));
            p("jsonu", JSON.Stringify(d, "", false));
            var parsed = JSON.ParseString("{\"z\":1,\"a\":[1.5,2,\"x\\n\",true,null,-0.001,1e3,12345678901234567890],\"m\":{\"k\":-0.001,\"u\":\"\\u00e9\\ud83d\\ude00\"}}");
            p("parse", parsed);
            p("parse_t", GD.TypeOf(parsed["z"]));
            p("restring", JSON.Stringify(parsed));
            p("parse_bad", JSON.ParseString("{bad"));
            p("parse_trail", JSON.ParseString("[1] x"));
            p("h_s", GD.Hash("abc"));
            p("h_s2", GD.Hash("wooden"));
            p("h_t", GD.Hash(true));
            p("h_n", GD.Hash(Var.Nil));
            p("h_a", GD.Hash(GArray.Of(1, 5, "wooden")));
            p("h_a2", GD.Hash(GArray.Of(0, 12, "golden")));
            p("h_e", GD.Hash(new GArray()));
            p("h_d", GD.Hash(GDict.Of("a", 1)));
            p("h_v", GD.Hash(new Vec2(1, 2)));
            p("h_v3", GD.Hash(new Vec3(1, 2, 3)));
            p("h_vi", GD.Hash(new Vec2i(1, 2)));
            p("h_nest", GD.Hash(GDict.Of("x", GArray.Of(1, 2.0, GDict.Of("y", "z")))));
            foreach (var s in new[] { "snake_case_word", "camelCaseWord", "HTTPServer", "player2Name", "hello world", "  multi   space ", "Already Cap", "x", "", "golem_king", "A1b2C3" })
                p("cap_" + s, s.Capitalize());
            foreach (var s in new[] { "12abc", "-5", "1x2", "3.7", "--5", "", "abc", "12-3", " 42", "+7", "007" })
            {
                p("toint_" + s, s.ToInt());
                p("isint_" + s, s.IsValidInt());
            }
            foreach (var s in new[] { "3.25", "1e3", "abc", ".5", "-0.5e-2", "12abc", "1.2.3", "0.30000000000000004", "123456789012345678901234", "4.35" })
            {
                p("tofloat_" + s, s.ToFloat());
                p("isfloat_" + s, s.IsValidFloat());
            }
            p("padz", "7".PadZeros(3) + "|" + "-7.5".PadZeros(4) + "|" + "1.25".PadDecimals(4) + "|" + "1.25".PadDecimals(1));
            p("split", Var.Of("a,b,,c".Split(",")));
            p("split2", Var.Of("a,b,,c".Split(",", false)));
            p("split3", Var.Of("a,b,,c".Split(",", true, 1)));
            p("split4", Var.Of("".Split(",", true)));
            p("slice", "a/b/c".GetSlice("/", 1) + "|" + "a/b/c".GetSlice("/", 5) + "|" + "abc".GetSlice("/", 0) + "|" + GD.Str("a/b/c".GetSliceCount("/")));
            p("lr", "hello".Left(2) + "|" + "hello".Left(-2) + "|" + "hello".Right(2) + "|" + "hello".Right(-2) + "|" + "hello".Substr(1, 3) + "|" + "hello".Substr(3) + "|" + "hello".Substr(9));
            p("strip", "[" + "  \t x y \n".StripEdges() + "]");
            p("find", GD.Fmt("%d %d %d %d", "hello".Find("l"), "hello".Find("l", 3), "hello".RFind("l"), "hello".Find("z")));
            p("paths", "res://a/b/c.png".GetFile() + "|" + "res://a/b/c.png".GetBasename() + "|" + "res://a/b/c.png".GetExtension() + "|" + "res://a/b/c.png".GetBaseDir() + "|" + "user://x".PathJoin("y.json"));
            p("join", GStr.Join(", ", new[] { "a", "b", GD.Str(3) }));
            p("count", "banana".Count("a"));
            p("trim", "prefix_name".TrimPrefix("prefix_") + "|" + "name.json".TrimSuffix(".json"));
            p("md5", "hello".Md5Text());
            p("sha", "hello".Sha256Text());
            p("uri", "a b&c/é".UriEncode());
            p("cmp", GD.Fmt("%d %d %d", "abc".NocasecmpTo("ABD"), "b".NocasecmpTo("a"), "abc".NocasecmpTo("ABC")));
            p("sim", "night".Similarity("nacht"));
            Var seven = 7, three = 3, two = 2;
            p("div", GD.Fmt("%s %s %s %s %s", seven / two, -seven / two, seven % three, -seven % three, 7.0 / 2));
            p("conv", GD.Fmt("%s %s %s %s %s", GD.Int(-2.5), GD.Int("12"), GD.Float("3.5x"), GD.Int(2.9999), GD.Int(-0.5)));
            p("eq", GD.Fmt("%s %s %s %s %s", (Var)1 == 1.0, (Var)GArray.Of(1) == GArray.Of(1.0), (Var)GDict.Of("a", 1) == GDict.Of("a", 1.0),
                (Var)GArray.Of(1, GArray.Of(2)) == GArray.Of(1, GArray.Of(2)), (Var)"a" == "a"));
            p("has", GD.Fmt("%s %s %s", GArray.Of(1, 2).Has(1.0), GDict.Of(1, "x").Has(1.0), GArray.Of(1.0).Has(1.0)));
            var arr = GArray.Of(3, 1, "a", 2.5, 2, -1, "B", 0.5);
            arr.Sort();
            p("sort", arr);
            var arr2 = GArray.Of(5, 3, 8, 1, 9, 2, 7, 4, 6, 0, 11, 15, 13, 12, 14, 10, 19, 17, 18, 16, 3, 3);
            arr2.SortCustom((a, b) => a % 5 < b % 5);
            p("sortc", arr2);
            var od = GDict.Of("x", 1, "y", 2, "z", 3);
            od.Erase("x");
            od["x"] = 4;
            od["w"] = 5;
            od.Erase("z");
            p("order", od);
            p("keys", od.Keys());
            GD.Seed(12345);
            p("rand", GD.Fmt("%d %s %s %d", GD.Randi(), GD.Randf(), GD.RandfRange(0.0, 10.0), GD.RandiRange(1, 6)));
            var sh = new GArray();
            for (int i = 0; i < 12; i++) sh.Append(i);
            sh.Shuffle();
            p("shuffle", sh);
            p("pick", GArray.Of(10, 20, 30, 40, 50).PickRandom());
            p("typeof", GD.Fmt("%d %d %d %d %d %d %d %d", GD.TypeOf(1), GD.TypeOf(1.0), GD.TypeOf("s"), GD.TypeOf(new GArray()), GD.TypeOf(new GDict()), GD.TypeOf(Var.Nil), GD.TypeOf(new Vec2()), GD.TypeOf(true)));
            p("slicea", GArray.Of(0, 1, 2, 3, 4, 5).Slice(1, -1));
            p("slicea2", GArray.Of(0, 1, 2, 3, 4, 5).Slice(-2));
            p("slicea3", GArray.Of(0, 1, 2, 3, 4, 5).Slice(5, 0, -2));
            p("maxmin", GD.Fmt("%s %s %s", GArray.Of(3, 9, 2).Max(), GArray.Of(3, 1.5, 2).Min(), new GArray().Max()));
            p("strarr", GD.Str(GArray.Of(1, 2.0, "s", Var.Nil, new Vec2(1, 2), GArray.Of(true), GDict.Of("k", "v"))));
            p("str_multi", GD.Str("a", 1, 2.5, Var.Nil));
            p("ease", GD.Fmt("%s %s %s", GD.Ease(0.3, 2.0), GD.Ease(0.3, -2.0), GD.Ease(0.7, 0.5)));
            p("wrap", GD.Fmt("%s %s %s", GD.Wrapf(370.0, 0.0, 360.0), GD.Wrapi(-1, 0, 5), GD.Pingpong(7.5, 3.0)));
            p("snapped", GD.Fmt("%s %s", GD.Snappedf(3.14159, 0.01), GD.Snappedi(17, 5)));
            p("lindb", GD.Fmt("%s %s", GD.LinearToDb(0.5), GD.DbToLinear(-6.0)));
        }
    }
}
