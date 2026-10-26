extends SceneTree
# Prints GDScript's results for the runtime cases tools/guitest (`runtime`) prints from the C# runtime (Sim/Script);
# tools/parity/runtime.sh diffs the two. Each line: "<case>|<result>".

func p(k: String, v) -> void:
	print(k + "|" + str(v))

func _init() -> void:
	var floats := [0.0, -0.0, 1.0, 0.1, 0.5, 1.0 / 3.0, 2.0 / 3.0, 1e15, 1e16, 123456.789, 1e-5, 1.5e-7, 3.14159265358979,
		100.0 / 7.0, -2.5, 1e20, 1.7976931348623157e308, 5e-324, 0.1 + 0.2, pow(2.0, -15), 12345678.9, 99.995, 0.125, 2.5,
		-1234.5678, 7e-10, 65536.0 * 65536.0 * 65536.0, 0.000123456789, 9.87654321e12]
	for i in floats.size():
		var f: float = floats[i]
		p("str%d" % i, f)
		p("f%d" % i, "%f" % f)
		p("f1_%d" % i, "%.1f" % f)
		p("f2_%d" % i, "%.2f" % f)
		p("f3_%d" % i, "%.3f" % f)
		p("f0_%d" % i, "%.0f" % f)
		p("f5w_%d" % i, "%8.3f|" % f)
		p("d%d" % i, "%d" % f)
		p("s%d" % i, "%s" % f)
		p("json%d" % i, JSON.stringify(f))
		p("hash%d" % i, hash(f))
		p("v2_%d" % i, Vector2(f, -f))
	var ints := [0, 1, -1, 7, -7, 255, 65535, 1000000, -2147483648, 9223372036854775807]
	for i in ints.size():
		var n: int = ints[i]
		p("i%d" % i, n)
		p("id%d" % i, "%05d|%-6d|%+d|%x|%X|%o|%3d" % [n, n, n, n, n, n, n])
		p("ih%d" % i, hash(n))
		p("ij%d" % i, JSON.stringify(n))
	p("vec2", Vector2(0.1, 2))
	p("vec3", Vector3(1.5, -0.25, 1e7))
	p("vec2i", Vector2i(3, -4))
	p("fmtv", "%.2v" % Vector2(1.234, -5.5))
	p("fmtc", "%c%c" % [65, "z"])
	p("fmts", "[%10s][%-10s][%s]" % ["ab", "cd", [1, "x"]])
	p("fmtstar", "%*d|%.*f" % [6, 42, 2, 3.14159])
	p("fmtpct", "100%%")
	var d := {"a": 1, "b": [1, 2.5, "x", null, true], "c": {"d": Vector2(1, 2), "e": "q\"uote\n"}, 5: "five", 2.5: "f"}
	p("strd", d)
	p("jsond", JSON.stringify(d))
	p("jsondi", JSON.stringify(d, "\t").replace("\n", "\\n").replace("\t", "\\t"))
	p("jsonu", JSON.stringify(d, "", false))
	var parsed = JSON.parse_string('{"z":1,"a":[1.5,2,"x\\n",true,null,-0.001,1e3,12345678901234567890],"m":{"k":-0.001,"u":"\\u00e9\\ud83d\\ude00"}}')
	p("parse", parsed)
	p("parse_t", typeof(parsed.z))
	p("restring", JSON.stringify(parsed))
	p("parse_bad", JSON.parse_string("{bad"))
	p("parse_trail", JSON.parse_string("[1] x"))
	p("h_s", hash("abc"))
	p("h_s2", hash("wooden"))
	p("h_t", hash(true))
	p("h_n", hash(null))
	p("h_a", hash([1, 5, "wooden"]))
	p("h_a2", hash([0, 12, "golden"]))
	p("h_e", hash([]))
	p("h_d", hash({"a": 1}))
	p("h_v", hash(Vector2(1, 2)))
	p("h_v3", hash(Vector3(1, 2, 3)))
	p("h_vi", hash(Vector2i(1, 2)))
	p("h_nest", hash({"x": [1, 2.0, {"y": "z"}]}))
	for s in ["snake_case_word", "camelCaseWord", "HTTPServer", "player2Name", "hello world", "  multi   space ", "Already Cap", "x", "", "golem_king", "A1b2C3"]:
		p("cap_" + s, s.capitalize())
	for s in ["12abc", "-5", "1x2", "3.7", "--5", "", "abc", "12-3", " 42", "+7", "007"]:
		p("toint_" + s, s.to_int())
		p("isint_" + s, s.is_valid_int())
	for s in ["3.25", "1e3", "abc", ".5", "-0.5e-2", "12abc", "1.2.3", "0.30000000000000004", "123456789012345678901234", "4.35"]:
		p("tofloat_" + s, s.to_float())
		p("isfloat_" + s, s.is_valid_float())
	p("padz", "7".pad_zeros(3) + "|" + "-7.5".pad_zeros(4) + "|" + "1.25".pad_decimals(4) + "|" + "1.25".pad_decimals(1))
	p("split", "a,b,,c".split(","))
	p("split2", "a,b,,c".split(",", false))
	p("split3", "a,b,,c".split(",", true, 1))
	p("split4", "".split(","))
	p("slice", "a/b/c".get_slice("/", 1) + "|" + "a/b/c".get_slice("/", 5) + "|" + "abc".get_slice("/", 0) + "|" + str("a/b/c".get_slice_count("/")))
	p("lr", "hello".left(2) + "|" + "hello".left(-2) + "|" + "hello".right(2) + "|" + "hello".right(-2) + "|" + "hello".substr(1, 3) + "|" + "hello".substr(3) + "|" + "hello".substr(9))
	p("strip", "[" + "  \t x y \n".strip_edges() + "]")
	p("find", "%d %d %d %d" % ["hello".find("l"), "hello".find("l", 3), "hello".rfind("l"), "hello".find("z")])
	p("paths", "res://a/b/c.png".get_file() + "|" + "res://a/b/c.png".get_basename() + "|" + "res://a/b/c.png".get_extension() + "|" + "res://a/b/c.png".get_base_dir() + "|" + "user://x".path_join("y.json"))
	p("join", ", ".join(["a", "b", str(3)]))
	p("count", "banana".count("a"))
	p("trim", "prefix_name".trim_prefix("prefix_") + "|" + "name.json".trim_suffix(".json"))
	p("md5", "hello".md5_text())
	p("sha", "hello".sha256_text())
	p("uri", "a b&c/é".uri_encode())
	p("cmp", "%d %d %d" % ["abc".nocasecmp_to("ABD"), "b".nocasecmp_to("a"), "abc".nocasecmp_to("ABC")])
	p("sim", "night".similarity("nacht"))
	p("div", "%s %s %s %s %s" % [7 / 2, -7 / 2, 7 % 3, -7 % 3, 7.0 / 2])
	p("conv", "%s %s %s %s %s" % [int(-2.5), int("12"), float("3.5x"), int(2.9999), int(-0.5)])
	p("eq", "%s %s %s %s %s" % [1 == 1.0, [1] == [1.0], {"a": 1} == {"a": 1.0}, [1, [2]] == [1, [2]], "a" == "a"])
	p("has", "%s %s %s" % [[1, 2].has(1.0), {1: "x"}.has(1.0), [1.0].has(1.0)])
	var arr := [3, 1, "a", 2.5, 2, -1, "B", 0.5]
	arr.sort()
	p("sort", arr)
	var arr2 := [5, 3, 8, 1, 9, 2, 7, 4, 6, 0, 11, 15, 13, 12, 14, 10, 19, 17, 18, 16, 3, 3]
	arr2.sort_custom(func(a, b): return a % 5 < b % 5)
	p("sortc", arr2)
	var od := {"x": 1, "y": 2, "z": 3}
	od.erase("x")
	od["x"] = 4
	od["w"] = 5
	od.erase("z")
	p("order", od)
	p("keys", od.keys())
	seed(12345)
	p("rand", "%d %s %s %d" % [randi(), randf(), randf_range(0.0, 10.0), randi_range(1, 6)])
	var sh := range(12)
	sh.shuffle()
	p("shuffle", sh)
	p("pick", [10, 20, 30, 40, 50].pick_random())
	p("typeof", "%d %d %d %d %d %d %d %d" % [typeof(1), typeof(1.0), typeof("s"), typeof([]), typeof({}), typeof(null), typeof(Vector2()), typeof(true)])
	p("slicea", [0, 1, 2, 3, 4, 5].slice(1, -1))
	p("slicea2", [0, 1, 2, 3, 4, 5].slice(-2))
	p("slicea3", [0, 1, 2, 3, 4, 5].slice(5, 0, -2))
	p("maxmin", "%s %s %s" % [[3, 9, 2].max(), [3, 1.5, 2].min(), [].max()])
	p("strarr", str([1, 2.0, "s", null, Vector2(1, 2), [true], {"k": "v"}]))
	p("str_multi", str("a", 1, 2.5, null))
	p("ease", "%s %s %s" % [ease(0.3, 2.0), ease(0.3, -2.0), ease(0.7, 0.5)])
	p("wrap", "%s %s %s" % [wrapf(370.0, 0.0, 360.0), wrapi(-1, 0, 5), pingpong(7.5, 3.0)])
	p("snapped", "%s %s" % [snappedf(3.14159, 0.01), snappedi(17, 5)])
	p("lindb", "%s %s" % [linear_to_db(0.5), db_to_linear(-6.0)])
	quit()
