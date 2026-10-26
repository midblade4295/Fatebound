extends SceneTree
# Prints Godot's results for the engine-services cases that tools/guitest (`services`) prints from the C# services
# (Sim/Script/GMarshal.cs, GUI/Services); tools/parity/services.sh diffs the two. Each line: "<case>|<result>".
#   - var_to_bytes / bytes_to_var / var_to_str / str_to_var of every Variant type the game sends or stores
#   - compression: Godot's blobs ("gz|" lines, embedded in the C# test) decompressed by C#, and C#'s blobs
#     ($FB_SERVICES_OUT/cs_blobs.txt, written by `guitest services-gen`) decompressed here
#   - PackedByteArray encode_* / decode_*, Marshalls base64, HashingContext, Time, ConfigFile (files cross-read),
#     FileAccess / DirAccess, RegEx, OS / Engine / DisplayServer answers, threads
#   - WebSocketPeer against ws_server.gd, HTTPRequest against $FB_HTTP_URL (a local python http.server)

const WsServer = preload("ws_server.gd")

var out_dir := "/tmp/fb-services"
var me := "gd"           # this side's folder under out_dir; the other side's is "cs"

func p(k: String, v) -> void:
	print(k + "|" + str(v))

func sha(b: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	if not b.is_empty():
		h.update(b)
	return h.finish().hex_encode()

func noise(n: int, seed: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(n)
	var x := seed
	for i in n:
		x = (x * 1103515245 + 12345) & 0x7fffffff
		b[i] = (x >> 16) & 255
	return b

func proto_msg() -> Dictionary:
	return {"t": "snap", "tick": 123456, "you": 3, "dt": 0.05, "u": PackedByteArray([1, 2, 3, 4, 5, 6, 7]),
		"h": [[1, 2, 300000], [4, -5, 6]], "p": {"x": 1.25, "y": -7.5, "name": "Kévin"}}

func values() -> Array:
	var negz := 1.0 / -INF
	var posz := absf(negz)      # (a 0.0 literal here would be pooled with negz's -0.0)
	return [
		["nil", null], ["true", true], ["false", false], ["i0", 0], ["i1", 1], ["im1", -1], ["imax32", 2147483647], ["i2_31", 2147483648],
		["imin32", -2147483648], ["imin32m1", -2147483649], ["imax64", 9223372036854775807], ["imin64", -9223372036854775807 - 1],
		["f0", posz], ["fneg0", negz], ["f1", 1.0], ["fhalf", 0.5], ["f01", 0.1], ["fthird", 1.0 / 3.0], ["f1e20", 1e20],
		["fbig", 3.4028234663852886e38], ["f1e39", 1e39], ["fsmall", 1.401298464324817e-45], ["finf", INF], ["fninf", -INF],
		["f123", 123.456], ["f1e5", 1e-5], ["f15e7", 1.5e-7], ["f1e15", 1e15], ["f1e16", 1e16], ["fm25", -2.5], ["f3", 3.0], ["f16m", 16777217.0],
		["s0", ""], ["s1", "a"], ["s3", "abc"], ["s4", "abcd"], ["s5", "abcde"], ["sutf", "héllo wörld"], ["sjp", "日本語"], ["semoji", "😀x"],
		["snl", "line1\nline2\ttab\\ \"q\""],
		["v2", Vector2(1.5, -2)], ["v2b", Vector2(0.1, 1e-3)], ["v2i", Vector2i(3, -4)], ["v3", Vector3(1, 2.5, -3)], ["r2", Rect2(1, 2, 3.5, 4)],
		["r2i", Rect2i(1, -2, 3, 4)], ["v3i", Vector3i(1, -2, 3)], ["v4", Vector4(1, 2.5, -3, 0.1)], ["v4i", Vector4i(1, 2, 3, -4)],
		["plane", Plane(0, 1, 0, 2.5)], ["quat", Quaternion(0, 0.7071068, 0, 0.7071068)], ["aabb", AABB(Vector3(1, 2, 3), Vector3(4, 5, 6))],
		["basis", Basis(Vector3(1, 0, 0), Vector3(0, 2, 0), Vector3(0, 0.5, 3))], ["t2d", Transform2D(Vector2(1, 2), Vector2(3, 4), Vector2(5, 6))],
		["t3d", Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)), Vector3(7, 8, 9))],
		["proj", Projection(Vector4(1, 0, 0, 0), Vector4(0, 2, 0, 0), Vector4(0, 0, 3, 0.5), Vector4(1, 2, 3, 1))],
		["col", Color(1, 0.5, 0.25, 1)], ["col2", Color(0.1, 0.2, 0.3, 0.4)],
		["pba0", PackedByteArray()], ["pba3", PackedByteArray([1, 2, 255])], ["pba5", PackedByteArray([0, 1, 2, 3, 4])],
		["pi32", PackedInt32Array([1, -2, 2147483647])], ["pi64", PackedInt64Array([1, -1, 1099511627776])],
		["pf32", PackedFloat32Array([0.5, 0.1, -3])], ["pf64", PackedFloat64Array([0.1, 1e300, -0.5])],
		["pstr", PackedStringArray(["a", "bc", "", "déf", "abc"])], ["pv2", PackedVector2Array([Vector2(1, 2), Vector2(-0.5, 3)])],
		["pv3", PackedVector3Array([Vector3(1, 2, 3)])], ["pcol", PackedColorArray([Color(1, 0, 0, 1), Color(0, 0.5, 1, 0.25)])],
		["pv4", PackedVector4Array([Vector4(1, 2, 3, 4)])],
		["d0", {}], ["a0", []],
		["dmix", {"a": 1, "b": [1, 2.5, "x", null, true], "c": {"d": Vector2(1, 2), "e": "q\"uote\n"}, 5: "five", 2.5: "f", Vector2i(1, 2): [], true: false}],
		["anest", [[1, [2, [3, []]]], {}, [{"k": PackedByteArray([7])}]]],
		["proto", proto_msg()],
		["dkeys", {"b": 1, "a": 2, 10: 3, 2: 4, 1.5: 5, Vector2(1, 0): 6, "B": 7, "é": 8, -1: 9, "": 10, false: 12, 2.0: 13}],
	]

# (str() of these is the GUI's own value types' business; their var_to_str and bytes are checked)
const NO_STR := ["col", "col2", "pcol", "r2", "t2d"]

func _init() -> void:
	if OS.has_environment("FB_SERVICES_OUT"):
		out_dir = OS.get_environment("FB_SERVICES_OUT")
	DirAccess.make_dir_recursive_absolute(out_dir + "/" + me)
	marshal_cases()
	compression_cases()
	bytes_cases()
	base64_hash_cases()
	time_cases()
	text_cases()
	config_cases()
	file_cases()
	regex_cases()
	misc_cases()
	thread_cases()
	logger_cases()
	ws_cases()
	# (HTTPRequest needs the tree, which is set up after _init: the first frame starts it)

# ---------------------------------------------------------------- var_to_bytes / bytes_to_var / var_to_str
func marshal_cases() -> void:
	for c in values():
		var name: String = c[0]
		var b := var_to_bytes(c[1])
		p("vb|" + name, b.hex_encode())
		p("vs|" + name, var_to_str(c[1]).c_escape())
		var back = bytes_to_var(b)
		p("rt|" + name, var_to_str(back).c_escape())
		p("ty|" + name, typeof(back))
		if not NO_STR.has(name):
			p("st|" + name, str(back).c_escape())
		p("rs|" + name, var_to_str(str_to_var(var_to_str(c[1]))).c_escape())
	# bad input
	p("bad1", bytes_to_var(PackedByteArray([1, 0, 0])))
	p("bad2", bytes_to_var(PackedByteArray([4, 0, 0, 0, 9, 0, 0, 0, 65])))
	p("bad3", bytes_to_var(PackedByteArray([99, 0, 0, 0])))
	p("bad4", bytes_to_var(PackedByteArray([24, 0, 0, 0, 0, 0, 0, 0])))
	# values only Godot makes (the port has no StringName, NodePath or typed containers): its bytes, decoded by both
	var td: Dictionary[String, int] = {"a": 1}
	var tdv: Dictionary[int, Vector2] = {3: Vector2(1, 2)}
	var gonly := [["strname", &"sname"], ["nodepath", NodePath("/root/a:b:c")], ["nodepath2", NodePath("a/b:c")],
		["typedarr", [1, 2] as Array[int]], ["typedarr_s", ["x"] as Array[String]], ["objarr", [] as Array[Node]],
		["typeddict", td], ["typeddict_vt", tdv]]
	for c in gonly:
		var gb := var_to_bytes(c[1])
		p("gvb|" + c[0], gb.hex_encode())
		p("grt|" + c[0], str(bytes_to_var(gb)).c_escape())
	# hand-made bytes: 64-bit reals, missing padding, bad UTF-8, a BOM, truncation, bad types
	var hand := ["05000100000000000000f83f00000000000000c0", "07000100000000000000f03f00000000000000400000000000000c400000000000001040",
		"23000100010000000000000000f83f00000000000000c0", "140001000000803f0000003f0000803e0000803f", "1d00000003000000010203",
		"0400000002000000fffe0000", "0400000005000000efbbbf4142000000", "040000000300000041004200", "1c000000ffffff7f", "02000000ff",
		"1b0000000100000002000000", "09000100000000000000f03f00000000000000400000000000000840", "220000000100000002000000414200000",
		"2200000001000000020000004142000000", "1c00010063000000000000000", "1c0001006300000000000000", "020001000100000000000000",
		"0e000100000000000000000000000000000000000000000000f03f0000000000000440", "25000000010000000000803f0000003f0000803e"]
	for h in hand:
		var hv = bytes_to_var(h.hex_decode()) if h.length() % 2 == 0 else null
		p("hand|" + h, "%d|%s" % [typeof(hv), var_to_str(hv).c_escape()])
	p("callable", var_to_bytes(func(): pass).hex_encode())
	for v in [NAN, 1.0 / -INF, 0.30000000000000004, 1e100, 123456789.0, 0.000123, 1e-4, 2.5e-5, 1e22, 5e-324, 4.9e-324 * 3, 0.1 + 0.7, 100.0, 1234567890123456.0, 12345678901234567.0]:
		p("vstr", var_to_str(v))

# ---------------------------------------------------------------- compression
func comp_inputs() -> Array:
	var text := ""
	for i in 200:
		text += "Fatebound siege %d; " % i
	return [["hello", "hello".to_utf8_buffer()], ["text", text.to_utf8_buffer()], ["proto", var_to_bytes(proto_msg())],
		["noise", noise(3000, 7)], ["one", PackedByteArray([42])]]

func compression_cases() -> void:
	var cs_blobs := {}
	var f := FileAccess.open(out_dir + "/cs_blobs.txt", FileAccess.READ)
	if f != null:
		while not f.eof_reached():
			var l := f.get_line()
			if l != "":
				var parts := l.split("|")
				cs_blobs[parts[0] + "|" + parts[1]] = parts[2].hex_decode()
	for mode in [FileAccess.COMPRESSION_DEFLATE, FileAccess.COMPRESSION_ZSTD, FileAccess.COMPRESSION_GZIP]:
		p("empty|%d" % mode, PackedByteArray().compress(mode).size())
		for c in comp_inputs():
			var name: String = c[0]
			var src: PackedByteArray = c[1]
			var z := src.compress(mode)
			var key := "%d|%s" % [mode, name]
			p("gz|" + key, z.hex_encode())
			var d := z.decompress(src.size(), mode)
			p("gd|" + key, "%d|%s" % [d.size(), sha(d)])
			p("gbig|" + key, z.decompress(src.size() + 100, mode).size())
			p("gsmall|" + key, z.decompress(maxi(1, src.size() - 1), mode).size())
			if mode != FileAccess.COMPRESSION_ZSTD:
				var dd := z.decompress_dynamic(-1, mode)
				p("gdyn|" + key, "%d|%s" % [dd.size(), sha(dd)])
				p("gdynlim|" + key, z.decompress_dynamic(src.size() - 1, mode).size())
			var cz: PackedByteArray = cs_blobs.get(key, PackedByteArray())
			var cd := cz.decompress(src.size(), mode) if not cz.is_empty() else PackedByteArray()
			p("cs|" + key, "%d|%s" % [cd.size(), sha(cd)])
			if mode != FileAccess.COMPRESSION_ZSTD and not cz.is_empty():
				var cdd := cz.decompress_dynamic(-1, mode)
				p("csdyn|" + key, "%d|%s" % [cdd.size(), sha(cdd)])
	# the online protocol's frame: "Z" + raw size + zstd(var_to_bytes(msg))
	var raw := var_to_bytes(proto_msg())
	var frame := PackedByteArray()
	frame.resize(5)
	frame[0] = 0x5A
	frame.encode_u32(1, raw.size())
	frame.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	var n := frame.decode_u32(1)
	p("zframe", var_to_str(bytes_to_var(frame.slice(5).decompress(n, FileAccess.COMPRESSION_ZSTD))).c_escape())
	p("badz", PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8]).decompress(100, FileAccess.COMPRESSION_ZSTD).size())
	p("badgz", PackedByteArray([31, 139, 8, 0, 1, 2, 3]).decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP).size())

# ---------------------------------------------------------------- PackedByteArray encode_* / decode_*
func bytes_cases() -> void:
	var b := PackedByteArray()
	b.resize(48)
	b.encode_u8(0, 255)
	b.encode_s8(1, -2)
	b.encode_u16(2, 65535)
	b.encode_s16(4, -300)
	b.encode_u32(6, 4000000000)
	b.encode_s32(10, -5)
	b.encode_u64(14, -1)
	b.encode_s64(22, -123456789012)
	b.encode_float(30, 0.1)
	b.encode_half(34, 1.5)
	b.encode_double(36, 2.5)
	b.encode_s16(44, 40000)
	b.encode_u8(46, -1)
	b.encode_u8(47, 256)
	b.encode_u32(46, 1)
	p("enc", b.hex_encode())
	p("dec", [b.decode_u8(0), b.decode_s8(1), b.decode_u16(2), b.decode_s16(4), b.decode_u32(6), b.decode_s32(10), b.decode_u64(14),
		b.decode_s64(22), b.decode_float(30), b.decode_half(34), b.decode_double(36), b.decode_s16(44), b.decode_u16(44), b.decode_s8(46)])
	p("dec_oob", [b.decode_u32(46), b.decode_u8(48), b.decode_s16(-1), b.decode_double(41)])
	var h := PackedByteArray()
	h.resize(16)
	var hv := [0.0, 1.0, -2.5, 65504.0, 70000.0, 1e-8, 0.333, 6.1e-5, -INF]
	for i in hv.size():
		if i * 2 < 16:
			h.encode_half(i * 2, hv[i])
	p("half", h.hex_encode())
	var hd := []
	for i in 8:
		hd.append(h.decode_half(i * 2))
	p("halfd", hd)
	var hs := PackedByteArray([0x01, 0x00, 0xff, 0x03, 0x00, 0x7c, 0x01, 0x7c])
	p("halfs", [hs.decode_half(0), hs.decode_half(2), hs.decode_half(4), is_nan(hs.decode_half(6))])
	var vb := PackedByteArray()
	vb.resize(64)
	p("encvar", vb.encode_var(4, {"a": [1, 2]}))
	p("decvar", var_to_str(vb.decode_var(4)).c_escape())
	p("decvarsize", vb.decode_var_size(4))
	p("hasvar", [vb.has_encoded_var(4), vb.has_encoded_var(62), vb.has_encoded_var(60)])
	p("encvar_nofit", vb.encode_var(60, "too long string"))
	var s5 := PackedByteArray([1, 2, 3, 4, 5])
	p("slice", [s5.slice(1, 3).hex_encode(), s5.slice(-2).hex_encode(), s5.slice(4, 2).hex_encode(), s5.slice(-10, 10).hex_encode(), s5.slice(5).hex_encode()])
	p("toarr", [PackedByteArray([1, 0, 0, 0, 255, 255, 255, 255]).to_int32_array(), PackedByteArray([0, 0, 128, 63, 1]).to_float32_array(),
		PackedByteArray([1, 0, 0, 0, 0, 0, 0, 128]).to_int64_array(), PackedByteArray([0, 0, 0, 0, 0, 0, 240, 63]).to_float64_array()])

# ---------------------------------------------------------------- base64, hashing, crypto
func base64_hash_cases() -> void:
	for arr in [PackedByteArray([0]), PackedByteArray([1, 2]), PackedByteArray([1, 2, 3]), noise(100, 3)]:
		var s := Marshalls.raw_to_base64(arr)
		p("b64", s)
		p("b64back", Marshalls.base64_to_raw(s).hex_encode())
	p("u8b64", Marshalls.utf8_to_base64("héllo 😀"))
	p("b64u8", Marshalls.base64_to_utf8(Marshalls.utf8_to_base64("héllo 😀")))
	p("u8b64e", Marshalls.utf8_to_base64(""))
	var vs := Marshalls.variant_to_base64({"a": [1, 2.5], "b": Vector2(1, 2)})
	p("vb64", vs)
	p("b64v", var_to_str(Marshalls.base64_to_variant(vs)).c_escape())
	p("b64nl", Marshalls.base64_to_raw("AQID\nBA==").hex_encode())
	for t in [HashingContext.HASH_MD5, HashingContext.HASH_SHA1, HashingContext.HASH_SHA256]:
		var h := HashingContext.new()
		p("hstart", [h.start(t), h.start(t)])
		h.update("abc".to_utf8_buffer())
		p("hempty", h.update(PackedByteArray()))
		h.update(noise(1000, 5))
		p("hash", h.finish().hex_encode())
		p("hfin2", h.finish().size())
		p("hupd", h.update(PackedByteArray([1])))
		h.start(t)
		h.update("abc".to_utf8_buffer())
		p("habc", h.finish().hex_encode())
	var cr := Crypto.new()
	p("rand", [cr.generate_random_bytes(10).size(), cr.generate_random_bytes(0).size()])
	p("hmac", cr.hmac_digest(HashingContext.HASH_SHA256, "key".to_utf8_buffer(), "The quick brown fox".to_utf8_buffer()).hex_encode())
	p("hmac1", cr.hmac_digest(HashingContext.HASH_SHA1, "k".to_utf8_buffer(), noise(200, 9)).hex_encode())
	p("ctc", [cr.constant_time_compare(PackedByteArray([1, 2]), PackedByteArray([1, 2])), cr.constant_time_compare(PackedByteArray([1, 2]), PackedByteArray([1, 3]))])

# ---------------------------------------------------------------- Time
func time_cases() -> void:
	var times := [0, 1, -1, 59, 86399, 86400, -86400, -86401, 951782400, 951868800, 1709164800, 1709251199, 4102444800, -2208988800,
		-62135596800, -62167219200, -62198755200, 253402300799, 1761500000, 10000000000, -100000000000, 1700000000, -11644473600]
	for t in times:
		var k := str(t)
		p("td|" + k, Time.get_datetime_dict_from_unix_time(t))
		p("tdd|" + k, Time.get_date_dict_from_unix_time(t))
		p("ttd|" + k, Time.get_time_dict_from_unix_time(t))
		p("ts|" + k, Time.get_datetime_string_from_unix_time(t))
		p("tss|" + k, Time.get_datetime_string_from_unix_time(t, true))
		p("tds|" + k, Time.get_date_string_from_unix_time(t))
		p("tts|" + k, Time.get_time_string_from_unix_time(t))
		var d := Time.get_datetime_dict_from_unix_time(t)
		p("tback|" + k, Time.get_unix_time_from_datetime_dict(d))
		p("tbacks|" + k, Time.get_unix_time_from_datetime_string(Time.get_datetime_string_from_unix_time(t)))
	p("tfloat", [Time.get_datetime_dict_from_unix_time(1700000000.9), Time.get_datetime_string_from_unix_time(-1.5)])
	for s in ["2024-02-29T12:34:56", "2024-02-29 12:34:56", "1999-12-31", "23:59:58", "-0005-03-01 01:02:03", "2023-02-29T00:00:00", "2020-13-01T00:00:00", "1970-01-01T00:00:60", "abc"]:
		p("tstr|" + s, [Time.get_datetime_dict_from_datetime_string(s, true), Time.get_datetime_dict_from_datetime_string(s, false), Time.get_unix_time_from_datetime_string(s)])
	p("tdictstr", [Time.get_datetime_string_from_datetime_dict({"year": 2020, "month": 5, "day": 6, "hour": 7}, false),
		Time.get_datetime_string_from_datetime_dict({"year": 2020, "month": 5, "day": 6, "hour": 7}, true),
		Time.get_datetime_string_from_datetime_dict({}, false), Time.get_datetime_string_from_datetime_dict({"month": 2, "day": 30}, false),
		Time.get_unix_time_from_datetime_dict({"year": 2000}), Time.get_unix_time_from_datetime_dict({"day": 0})])
	p("toff", [Time.get_offset_string_from_offset_minutes(-420), Time.get_offset_string_from_offset_minutes(330), Time.get_offset_string_from_offset_minutes(0), Time.get_offset_string_from_offset_minutes(-61)])
	var sys := Time.get_datetime_dict_from_system()
	p("sysk", sys.keys())
	var types := []
	for key in sys:
		types.append(typeof(sys[key]))
	p("syst", types)
	p("sysk2", [Time.get_date_dict_from_system().keys(), Time.get_time_dict_from_system(true).keys(), Time.get_datetime_dict_from_system(true).dst])
	p("sysdst", sys.dst)
	var utc := Time.get_datetime_dict_from_system(true)
	var loc := Time.get_datetime_dict_from_system()
	var u := int(Time.get_unix_time_from_system())
	p("offmin", roundi((Time.get_unix_time_from_datetime_dict(loc) - Time.get_unix_time_from_datetime_dict(utc)) / 60.0))
	p("bias", Time.get_time_zone_from_system().bias)
	p("utcmatch", absi(Time.get_unix_time_from_datetime_dict(utc) - u) <= 2)
	p("sysweek", sys.weekday == Time.get_datetime_dict_from_unix_time(Time.get_unix_time_from_datetime_dict(sys)).weekday)
	p("ticks", [Time.get_ticks_msec() >= 0, Time.get_ticks_usec() >= Time.get_ticks_msec(), Time.get_unix_time_from_system() > 1.7e9])
	p("sysstr", [Time.get_datetime_string_from_system().length(), Time.get_datetime_string_from_system(false, true).find(" "),
		Time.get_datetime_string_from_system(true).find("T"), Time.get_date_string_from_system().length(), Time.get_time_string_from_system(true).length()])

# ---------------------------------------------------------------- str_to_var
func text_cases() -> void:
	var cases := ["Vector2(1, 2)", "[1, 2.5, \"x\", null, true]", "{\n\"a\": 1,\n2: [3]\n}", "PackedByteArray(\"AQID\")", "PackedByteArray(1, 2, 3)",
		"Color(1, 0, 0, 1)", "#ff8000", "#f80c", "  42  ", "-7", "1e5", "2.", "nan", "inf_neg", "-inf", "inf",
		"\"esc\\n\\t\\u00e9\\U01F600 \\\"q\\\" \\ud83d\\ude00\"", "Rect2i(1, 2, 3, 4)", "{bad", "", "Vector3(1, inf, -2)",
		"PackedStringArray(\"a\", \"b\\\"c\")", "PackedFloat32Array(0.1, 2)", "PackedInt64Array(9223372036854775807, -5)",
		"Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 1, 2, 3)", "true", "nil", "Vector2i(1.9, -2.9)", "[1,,2]", "; comment\n5",
		"PackedColorArray(1, 0, 0, 1, 0.5, 0.5, 0.5, 1)", "Quaternion(0, 0, 0, 1)", "9999999999999999999", "Vector2(1)", "PackedVector2Array(1, 2, 3)",
		"Basis(1, 2, 3, 4, 5, 6, 7, 8, 9)", "AABB(1, 2, 3, 4, 5, 6)", "Plane(1, 0, 0, 5)", "Projection(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)",
		"Transform2D(1, 0, 0, 1, 5, 6)", "Vector4i(1, 2, 3, 4)", "Vector3i(-1, 0, 1)", "\"unterminated", "[1, 2", "0x10", "1_000"]
	for s in cases:
		var v = str_to_var(s)
		p("parse|" + s.c_escape(), "%d|%s" % [typeof(v), var_to_str(v).c_escape()])
	for s in ["Dictionary[String, int]({\n\"a\": 1\n})", "Array[int]([1, 2])", "Array[String]([\"x\"])"]:
		var v = str_to_var(s)
		p("parsestr|" + s.c_escape(), "%d|%s" % [typeof(v), str(v)])

# ---------------------------------------------------------------- ConfigFile
func cfg_build() -> ConfigFile:
	var c := ConfigFile.new()
	c.set_value("audio", "muted", true)
	c.set_value("audio", "volume", 0.8)
	c.set_value("", "top", 1)
	c.set_value("player", "name", "Kévin \"K\"\nline2")
	c.set_value("player", "pos", Vector2(1, 2))
	c.set_value("player", "list", [1, "a", {"k": [], "z": 2, "b": null}])
	c.set_value("player", "my key", 5)
	c.set_value("player", "k=v;x", PackedByteArray([1, 2, 3]))
	c.set_value("odd]name", "x", Color(1, 0.5, 0, 1))
	c.set_value("audio", "gone", 3)
	c.set_value("audio", "gone", null)
	c.set_value("empty", "a", 1)
	c.erase_section_key("empty", "a")
	c.set_value("nums", "big", 9223372036854775807)
	c.set_value("nums", "f", 1.0 / 3.0)
	c.set_value("nums", "neg", -0.5)
	c.set_value("nums", "e", 1e-7)
	c.set_value("nums", "arr", PackedInt32Array([1, 2]))
	c.set_value("", "second_top", "x")
	return c

func cfg_dump(tag: String, c: ConfigFile) -> void:
	p(tag + "|text", c.encode_to_text().c_escape())
	p(tag + "|secs", c.get_sections())
	for s in c.get_sections():
		var kv := []
		for k in c.get_section_keys(s):
			kv.append(k + "=" + var_to_str(c.get_value(s, k)))
		p(tag + "|sec|" + s, str(kv).c_escape())

func config_cases() -> void:
	var c := cfg_build()
	cfg_dump("cfg", c)
	p("cfghas", [c.has_section("empty"), c.has_section("audio"), c.has_section_key("audio", "muted"), c.has_section_key("audio", "gone"), c.has_section_key("nope", "x")])
	p("cfgget", [c.get_value("audio", "muted"), c.get_value("audio", "nope", 42), c.get_value("nope", "x", "d")])
	var path := out_dir + "/" + me + "/cfg.cfg"
	p("cfgsave", c.save(path))
	p("cfgsha", sha(FileAccess.get_file_as_bytes(path)))
	var c2 := ConfigFile.new()
	p("cfgload", c2.load(path))
	cfg_dump("cfgl", c2)
	var cx := ConfigFile.new()
	p("cfgx_load", cx.load(out_dir + "/cs/cfg.cfg"))
	cfg_dump("cfgx", cx)
	var cy := ConfigFile.new()
	p("cfgy_load", cy.load(path))
	cfg_dump("cfgy", cy)
	var text := "; comment\ntop_level=5\n[sec one]\na = 1\n\"quoted key\" = \"v\"\nb={\n\"x\": [1, 2],\n\"y\": Vector2(3, 4)\n}\n[sec\\]two]\nc=PackedStringArray(\"a\", \"b\")\nd=null\n[sec one]\ne=-1.5e-3\n"
	var c3 := ConfigFile.new()
	p("cfgparse", c3.parse(text))
	cfg_dump("cfgp", c3)
	var c4 := ConfigFile.new()
	p("cfgbad", c4.parse("[ok]\na=1\nb={bad\n"))
	cfg_dump("cfgb", c4)
	p("cfgmissing", ConfigFile.new().load(out_dir + "/nope.cfg"))
	c.erase_section("audio")
	c.clear()
	p("cfgclear", c.get_sections())

# ---------------------------------------------------------------- FileAccess / DirAccess
func file_cases() -> void:
	var D := out_dir + "/" + me + "/fa"
	DirAccess.make_dir_recursive_absolute(D + "/sub/deep")
	var f := FileAccess.open(D + "/a.txt", FileAccess.WRITE)
	f.store_string("héllo\n")
	f.store_line("line2")
	f.store_string("crlf\r\nlast-no-newline")
	f.close()
	f = FileAccess.open(D + "/a.txt", FileAccess.READ)
	p("fa_len", f.get_length())
	var lines := []
	while not f.eof_reached():
		lines.append(f.get_line())
	p("fa_lines", lines)
	p("fa_pos", [f.get_position(), f.eof_reached(), f.get_error()])
	f.seek(0)
	p("fa_eof2", [f.eof_reached(), f.get_error()])
	p("fa_buf", [f.get_buffer(3).hex_encode(), f.get_position()])
	p("fa_text", [f.get_as_text().c_escape(), f.get_position()])
	f.seek_end(-4)
	p("fa_tail", [f.get_buffer(10).get_string_from_utf8(), f.eof_reached(), f.get_error()])
	p("fa_len2", [f.get_length(), f.eof_reached()])
	f.close()
	p("fa_closed", f.is_open())
	f = FileAccess.open(D + "/b.bin", FileAccess.WRITE)
	f.store_8(300)
	f.store_16(-2)
	f.store_32(4000000000)
	f.store_64(-5)
	f.store_float(0.1)
	f.store_double(0.1)
	f.store_half(1.5)
	f.big_endian = true
	f.store_32(0x01020304)
	f.store_16(0x0506)
	f.big_endian = false
	f.store_var({"k": [1, 2.5]})
	f.store_pascal_string("pas")
	f.store_buffer(PackedByteArray([9, 8]))
	f.store_csv_line(PackedStringArray(["a", "b,c", "d\"e"]))
	f.close()
	p("fa_bhex", FileAccess.get_file_as_bytes(D + "/b.bin").hex_encode())
	f = FileAccess.open(D + "/b.bin", FileAccess.READ)
	p("fa_bvals", [f.get_8(), f.get_16(), f.get_32(), f.get_64(), f.get_float(), f.get_double(), f.get_half()])
	f.big_endian = true
	p("fa_bbe", [f.get_32(), f.get_16()])
	f.big_endian = false
	p("fa_bvar", var_to_str(f.get_var()).c_escape())
	p("fa_bpas", f.get_pascal_string())
	p("fa_bbuf", f.get_buffer(2).hex_encode())
	p("fa_csv", f.get_csv_line())
	p("fa_brest", [f.get_buffer(100).hex_encode(), f.eof_reached(), f.get_8(), f.get_32()])
	f.close()
	f = FileAccess.open(D + "/a.txt", FileAccess.READ_WRITE)
	f.seek_end()
	f.store_string("+more")
	f.close()
	p("fa_afull", FileAccess.get_file_as_string(D + "/a.txt").c_escape())
	p("fa_missing", [FileAccess.open(D + "/nope.txt", FileAccess.READ) == null, FileAccess.get_open_error()])
	p("fa_missingdir", [FileAccess.open(D + "/nodir/x.txt", FileAccess.WRITE) == null, FileAccess.get_open_error()])
	p("fa_isdir", [FileAccess.open(D + "/sub", FileAccess.READ) == null, FileAccess.get_open_error()])
	p("fa_rw_missing", [FileAccess.open(D + "/nope2", FileAccess.READ_WRITE) == null, FileAccess.get_open_error()])
	p("fa_ok_err", [FileAccess.open(D + "/a.txt", FileAccess.READ) != null, FileAccess.get_open_error()])
	p("fa_gfas_missing", [FileAccess.get_file_as_string(D + "/nope.txt"), FileAccess.get_open_error(), FileAccess.get_file_as_bytes(D + "/nope.txt").size()])
	p("fa_exists", [FileAccess.file_exists(D + "/a.txt"), FileAccess.file_exists(D + "/nope"), FileAccess.file_exists(D + "/sub")])
	f = FileAccess.open(D + "/c.txt", FileAccess.WRITE_READ)
	f.store_string("abc")
	f.seek(0)
	p("fa_wr", [f.get_as_text(), f.get_line()])
	f.close()
	f = FileAccess.open(D + "/bom.txt", FileAccess.WRITE)
	f.store_buffer(PackedByteArray([0xEF, 0xBB, 0xBF, 0x41, 0x42, 0x00, 0x43]))
	f.close()
	p("fa_bom", [FileAccess.get_file_as_string(D + "/bom.txt"), FileAccess.open(D + "/bom.txt", FileAccess.READ).get_as_text()])
	p("fa_copy", [DirAccess.copy_absolute(D + "/a.txt", D + "/sub/a_copy.txt"), FileAccess.get_file_as_string(D + "/sub/a_copy.txt").length()])
	p("fa_rename", DirAccess.rename_absolute(D + "/c.txt", D + "/sub/c2.txt"))
	p("fa_rename_over", DirAccess.rename_absolute(D + "/sub/c2.txt", D + "/sub/a_copy.txt"))
	p("fa_after_over", FileAccess.get_file_as_string(D + "/sub/a_copy.txt"))
	p("fa_rename_missing", DirAccess.rename_absolute(D + "/nope", D + "/nope2"))
	f = FileAccess.open(D + "/.hidden", FileAccess.WRITE)
	f.store_string("h")
	f.close()
	var d := DirAccess.open(D)
	p("fa_files", d.get_files())
	p("fa_dirs", d.get_directories())
	d.include_hidden = true
	p("fa_files_h", d.get_files())
	d.include_navigational = true
	p("fa_dirs_nav", d.get_directories())
	p("fa_dirat", DirAccess.get_files_at(D + "/sub"))
	p("fa_direx", [DirAccess.dir_exists_absolute(D + "/sub/deep"), DirAccess.dir_exists_absolute(D + "/nope"), DirAccess.dir_exists_absolute(D + "/a.txt")])
	p("fa_rm", [DirAccess.remove_absolute(D + "/sub"), DirAccess.remove_absolute(D + "/sub/a_copy.txt"), DirAccess.remove_absolute(D + "/sub/deep"), DirAccess.remove_absolute(D + "/nope")])
	p("fa_mkdir", [DirAccess.make_dir_absolute(D + "/sub"), DirAccess.make_dir_recursive_absolute(D + "/x/y/z"), DirAccess.make_dir_absolute(D + "/q/r"), DirAccess.make_dir_absolute(D + "/q")])
	p("fa_open_missing", [DirAccess.open(D + "/nope") == null, DirAccess.get_open_error()])
	d = DirAccess.open(D + "/x")
	d.list_dir_begin()
	var names := []
	var n := d.get_next()
	while n != "":
		names.append([n, d.current_is_dir()])
		n = d.get_next()
	d.list_dir_end()
	p("fa_list", names)
	p("fa_rel", [d.file_exists("y"), d.dir_exists("y"), d.make_dir("w"), DirAccess.dir_exists_absolute(D + "/x/w")])
	var ff := FileAccess.open(D + "/x/w/f.txt", FileAccess.WRITE)
	ff.store_string("1")
	ff.close()
	p("fa_rm_rel", [d.remove("w/f.txt"), d.remove("w"), DirAccess.dir_exists_absolute(D + "/x/w")])

# ---------------------------------------------------------------- RegEx
func regex_cases() -> void:
	var rx := RegEx.new()
	p("rx_compile", rx.compile("(?<![\\w])(gate|tower|King\\!)(?![\\w])"))
	p("rx_sub", rx.sub("Take the tower, then the gate. King! towers", "[color=x]$1[/color]", true))
	p("rx_sub1", rx.sub("Take the tower, then the gate.", "<$1>"))
	p("rx_sub_off", rx.sub("gate gate gate", "G", true, 2))
	p("rx_sub_end", rx.sub("gate gate gate", "G", true, 0, 9))
	var rx2 := RegEx.create_from_string("(?<word>[a-z]+)(?<num>\\d+)?")
	var m := rx2.search("  abc12 de x9", 0)
	p("rx_m", [m.get_string(), m.get_string("word"), m.get_string("num"), m.get_start(), m.get_end(), m.get_start("num"), m.get_end(2), m.get_group_count(), m.get_strings(), m.get_names(), m.get_subject()])
	var m2 := rx2.search("de x9")
	p("rx_m2", [m2.get_string(), m2.get_string("num"), m2.get_start("num"), m2.get_string(5), m2.get_start(5), m2.get_names(), m2.get_strings()])
	var ss := []
	for mm in rx2.search_all("abc12 de x9"):
		ss.append([mm.get_string(), mm.get_string(2), mm.get_start(2)])
	p("rx_all", ss)
	p("rx_all_off", rx2.search_all("abc12 de x9", 4).size())
	p("rx_offset", rx2.search("abc def", 3).get_string())
	p("rx_end", rx2.search("abcdef", 0, 3).get_string())
	p("rx_none", rx2.search("123") == null)
	p("rx_named_sub", rx2.sub("ab1 cd2", "${num}-$word $$", true))
	p("rx_bad", RegEx.create_from_string("(unclosed", false).is_valid())
	p("rx_names", [rx2.get_names(), rx2.get_group_count(), rx2.get_pattern(), rx2.is_valid()])

# ---------------------------------------------------------------- OS / Engine / DisplayServer / settings
func misc_cases() -> void:
	p("os", [OS.get_name(), DisplayServer.get_name(), OS.get_model_name(), OS.get_locale(), OS.get_locale_language(), OS.get_version()])
	p("os_procs", OS.get_processor_count())
	p("os_thread", [OS.get_thread_caller_id(), OS.get_main_thread_id()])
	p("os_env", [OS.has_environment("HOME"), OS.get_environment("FB_NOPE_X"), OS.has_environment("FB_NOPE_X"), OS.get_environment("HOME") != ""])
	OS.set_environment("FB_SVC_TEST", "v1")
	p("os_env_set", [OS.has_environment("FB_SVC_TEST"), OS.get_environment("FB_SVC_TEST")])
	OS.unset_environment("FB_SVC_TEST")
	p("os_env_unset", OS.has_environment("FB_SVC_TEST"))
	p("os_debug", OS.is_debug_build())
	p("os_features", [OS.has_feature("pc"), OS.has_feature("linux"), OS.has_feature("mobile"), OS.has_feature("android"), OS.has_feature("64"), OS.has_feature("debug"), OS.has_feature("release"), OS.has_feature("x86_64")])
	p("os_dirs", [OS.get_user_data_dir() != "", OS.get_cache_dir() != ""])
	p("engine_ver", Engine.get_version_info())
	p("engine", [Engine.max_fps, Engine.physics_ticks_per_second, Engine.time_scale])
	Engine.max_fps = 30
	p("engine_maxfps", Engine.max_fps)
	Engine.max_fps = 0
	p("ds", [DisplayServer.window_get_size(), DisplayServer.screen_get_refresh_rate(), DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD), DisplayServer.FEATURE_VIRTUAL_KEYBOARD, DisplayServer.FEATURE_CLIPBOARD])
	p("perf", [Performance.TIME_PROCESS, Performance.TIME_PHYSICS_PROCESS, Performance.OBJECT_COUNT, Performance.OBJECT_NODE_COUNT, Performance.RENDER_VIDEO_MEM_USED,
		Performance.RENDER_TEXTURE_MEM_USED, Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME, Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME, Performance.MEMORY_STATIC])
	p("plugins", [Engine.has_singleton("GodotGooglePlayBilling"), ClassDB.class_exists("GameCenterManager"), ClassDB.can_instantiate("GKAchievement")])
	p("pset", [ProjectSettings.get_setting("application/config/version", "x"), ProjectSettings.get_setting("nope/nope", 5), ProjectSettings.load_resource_pack("/nope.pck", false)])
	p("consts", [FileAccess.READ, FileAccess.WRITE, FileAccess.READ_WRITE, FileAccess.WRITE_READ, FileAccess.COMPRESSION_DEFLATE, FileAccess.COMPRESSION_ZSTD, FileAccess.COMPRESSION_GZIP,
		HTTPClient.METHOD_POST, HTTPClient.STATUS_BODY, HTTPRequest.RESULT_SUCCESS, HTTPRequest.RESULT_TIMEOUT, WebSocketPeer.STATE_CLOSED, HashingContext.HASH_SHA256, Logger.ERROR_TYPE_SCRIPT,
		Time.WEEKDAY_SATURDAY, Time.MONTH_DECEMBER, Thread.PRIORITY_HIGH])

# ---------------------------------------------------------------- threads
func thread_cases() -> void:
	var th := Thread.new()
	p("th_start", th.start(func(): return 21 * 2))
	p("th_again", th.start(func(): return 0))
	p("th_wait", th.wait_to_finish())
	p("th_started", [th.is_started(), th.is_alive()])
	var mtx := Mutex.new()
	mtx.lock()
	p("mtx_try", mtx.try_lock())
	mtx.unlock()
	mtx.unlock()
	var sem := Semaphore.new()
	p("sem", [sem.try_wait()])
	sem.post()
	p("sem2", [sem.try_wait(), sem.try_wait()])
	var counter := [0]
	var tid := WorkerThreadPool.add_task(func(): counter[0] = 7)
	p("wtp", [WorkerThreadPool.wait_for_task_completion(tid), counter[0]])
	var other := [0]
	var th2 := Thread.new()
	th2.start(func(): other[0] = OS.get_thread_caller_id())
	th2.wait_to_finish()
	p("th_id", [other[0] != OS.get_thread_caller_id(), other[0] > 1])

# ---------------------------------------------------------------- OS.add_logger
class Cap:
	extends Logger
	var got := []
	func _log_message(message: String, error: bool) -> void:
		got.append(["msg", message, error])
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		got.append(["err", function, file.get_file(), line, code, rationale, error_type])

func logger_cases() -> void:
	var cap := Cap.new()
	OS.add_logger(cap)
	print("logged line")
	push_error("an error")
	push_warning("a warning")
	OS.remove_logger(cap)
	print("not logged")
	p("logger", str(cap.got).c_escape())

# ---------------------------------------------------------------- WebSocketPeer (against ws_server.gd in-process)
var srv = null

func ws_poll(ws: WebSocketPeer) -> void:
	if srv != null:
		srv.step()
	ws.poll()
	OS.delay_msec(2)

func ws_wait_state(ws: WebSocketPeer, want: int) -> int:
	var t0 := Time.get_ticks_msec()
	while ws.get_ready_state() != want and Time.get_ticks_msec() - t0 < 5000:
		ws_poll(ws)
	return ws.get_ready_state()

func ws_wait_packet(ws: WebSocketPeer) -> PackedByteArray:
	var t0 := Time.get_ticks_msec()
	while ws.get_available_packet_count() == 0 and Time.get_ticks_msec() - t0 < 5000:
		ws_poll(ws)
	return ws.get_packet()

func ws_cases() -> void:
	srv = WsServer.new()
	var url := "ws://127.0.0.1:%d/" % srv.start(0)
	var ws := WebSocketPeer.new()
	ws.outbound_buffer_size = 1 << 17
	p("ws_state0", [ws.get_ready_state(), ws.get_close_code(), ws.get_available_packet_count()])
	p("ws_connect", ws.connect_to_url(url))
	p("ws_connecting", ws.get_ready_state())
	p("ws_again", ws.connect_to_url(url))
	p("ws_open", ws_wait_state(ws, WebSocketPeer.STATE_OPEN))
	p("ws_proto", ws.get_selected_protocol())
	p("ws_put", ws.put_packet(var_to_bytes({"t": "hi", "n": 1, "v": Vector2(1, 2), "s": "héllo"})))
	var pkt := ws_wait_packet(ws)
	p("ws_echo1", [var_to_str(bytes_to_var(pkt)).c_escape(), ws.was_string_packet(), ws.get_packet_error()])
	p("ws_text", ws.send_text("hello ws"))
	pkt = ws_wait_packet(ws)
	p("ws_echo2", [pkt.get_string_from_utf8(), ws.was_string_packet()])
	var big := noise(50000, 11)
	p("ws_big", ws.put_packet(var_to_bytes(big)))
	pkt = ws_wait_packet(ws)
	var bigback = bytes_to_var(pkt)
	p("ws_echo3", [bigback.size(), sha(bigback), ws.was_string_packet()])
	p("ws_none", [ws.get_available_packet_count(), ws.get_packet().size(), ws.get_packet_error()])
	p("ws_bye", ws.put_packet(var_to_bytes({"t": "bye"})))
	var msgs := []
	var t0 := Time.get_ticks_msec()
	while ws.get_ready_state() != WebSocketPeer.STATE_CLOSED and Time.get_ticks_msec() - t0 < 5000:
		ws_poll(ws)
		while ws.get_available_packet_count() > 0:
			msgs.append(var_to_str(bytes_to_var(ws.get_packet())).c_escape())
	p("ws_msgs", msgs)
	p("ws_closed", [ws.get_ready_state(), ws.get_close_code(), ws.get_close_reason(), ws.get_available_packet_count()])
	p("ws_put_closed", ws.put_packet(PackedByteArray([1])))
	var ws2 := WebSocketPeer.new()
	ws2.connect_to_url(url)
	p("ws2_open", ws_wait_state(ws2, WebSocketPeer.STATE_OPEN))
	ws2.close(1000, "done")
	p("ws2_closing", ws2.get_ready_state())
	p("ws2_closed", [ws_wait_state(ws2, WebSocketPeer.STATE_CLOSED), ws2.get_close_code(), ws2.get_close_reason()])
	p("ws2_reconnect", ws2.connect_to_url(url))
	p("ws2_reopen", [ws_wait_state(ws2, WebSocketPeer.STATE_OPEN), ws2.get_close_code()])
	ws2.close()
	ws_wait_state(ws2, WebSocketPeer.STATE_CLOSED)
	var ws3 := WebSocketPeer.new()
	ws3.connect_to_url("ws://127.0.0.1:1/")
	p("ws3_refused", [ws_wait_state(ws3, WebSocketPeer.STATE_CLOSED), ws3.get_close_code()])
	var ws4 := WebSocketPeer.new()
	p("ws4_bad", [ws4.connect_to_url("http://127.0.0.1:1/"), ws4.get_ready_state()])
	var ws5 := WebSocketPeer.new()
	ws5.connect_to_url(url)
	ws5.close()
	p("ws5_abort", [ws5.get_ready_state(), ws5.get_close_code()])
	srv = null

# ---------------------------------------------------------------- HTTPRequest (against $FB_HTTP_URL)
var http_cases := []
var http_i := -1
var http: HTTPRequest
var http_done := true

func http_start() -> void:
	if not OS.has_environment("FB_HTTP_URL"):
		p("http", "skipped (no FB_HTTP_URL)")
		return
	var base := OS.get_environment("FB_HTTP_URL")
	http_cases = [
		{"name": "get", "url": base + "/a.txt"},
		{"name": "missing", "url": base + "/missing.txt"},
		{"name": "post", "url": base + "/a.txt", "method": HTTPClient.METHOD_POST, "body": "x=1", "headers": ["Content-Type: application/x-www-form-urlencoded"]},
		{"name": "head", "url": base + "/a.txt", "method": HTTPClient.METHOD_HEAD},
		{"name": "range", "url": base + "/a.txt", "headers": ["Range: bytes=0-9"]},
		{"name": "limit", "url": base + "/a.txt", "limit": 10},
		{"name": "download", "url": base + "/data.bin", "file": out_dir + "/" + me + "/dl.bin"},
		{"name": "refused", "url": "http://127.0.0.1:1/x"},
	]
	http = HTTPRequest.new()
	p("http_notree", http.request(base + "/a.txt"))
	root.add_child(http)
	http.request_completed.connect(_on_http)
	http_done = false
	_http_next()

func _http_next() -> void:
	http_i += 1
	if http_i >= http_cases.size():
		http_done = true
		return
	var c: Dictionary = http_cases[http_i]
	http.body_size_limit = c.get("limit", -1)
	http.download_file = c.get("file", "")
	var err := http.request(c.url, PackedStringArray(c.get("headers", [])), c.get("method", HTTPClient.METHOD_GET), c.get("body", ""))
	p("http_req|" + c.name, err)
	if http_i == 0:
		p("http_busy", http.request(c.url))

func _on_http(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	var c: Dictionary = http_cases[http_i]
	var cl := ""
	for h in headers:
		if h.to_lower().begins_with("content-length:"):
			cl = h.substr(15).strip_edges()
	var extra := ""
	if c.has("file"):
		extra = sha(FileAccess.get_file_as_bytes(c.file))
	p("http|" + c.name, [result, code, body.size(), sha(body) if body.size() > 0 else "", cl, extra, headers.size() > 0])
	_http_next.call_deferred()

var frames := 0

func _process(_delta: float) -> bool:
	frames += 1
	if frames == 1:
		http_start()
	if http_done or frames > 3000:
		if not http_done:
			p("http", "timed out")
		return true
	OS.delay_msec(2)
	return false
