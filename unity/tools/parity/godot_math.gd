extends SceneTree
# Prints Godot's results for Godot's math value types (Vector2/2i/3/3i/4/4i, Basis, Quaternion, Transform3D, AABB, Plane,
# Projection, Transform2D, Rect2, Color); tools/guitest (`math`, MathTest.cs) prints the same cases from the C# ports
# (Sim/Core, GUI/Core/Math2DGodot.cs) and tools/parity/math.sh diffs the two. Each line: "<case>|<str(result)>".

func p(k: String, v) -> void:
	print(k + "|" + str(v))

var V2 := [Vector2(0, 0), Vector2(1, 0), Vector2(3, -4), Vector2(0.1, 0.2), Vector2(-2.5, 7.25), Vector2(1e-6, -1e-6), Vector2(0.6, 0.8), Vector2(-1, -1)]
var V3 := [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 2, 3), Vector3(-0.5, 0.25, 2), Vector3(0.1, 0.2, 0.3),
	Vector3(1e-6, 0, -1e-6), Vector3(0.6, 0, 0.8), Vector3(-3, 4, -12), Vector3(0, 0, -1)]
var EUL := [Vector3(0, 0, 0), Vector3(0.1, 0.2, 0.3), Vector3(1.0, -2.0, 3.0), Vector3(PI / 2, 0.3, 0.2), Vector3(-PI / 2, 0.1, 0),
	Vector3(0.3, PI / 2, 0.2), Vector3(0.2, 0.1, -PI / 2), Vector3(0.5, 0, 0), Vector3(0, 0.7, 0), Vector3(0, PI, 0), Vector3(PI, 0, 0), Vector3(-1.2, 0.4, 2.9)]

func _init() -> void:
	vec2_cases()
	vec2i_cases()
	vec3_cases()
	vec34i_cases()
	basis_cases()
	quat_cases()
	xform3_cases()
	aabb_cases()
	plane_cases()
	projection_cases()
	xform2_cases()
	rect2_cases()
	color_cases()
	variant_cases()
	edge_cases()
	quit()

func vec2_cases() -> void:
	for i in V2.size():
		var a: Vector2 = V2[i]
		var k := "v2.%d." % i
		p(k + "len", a.length()); p(k + "lsq", a.length_squared()); p(k + "ang", a.angle()); p(k + "asp", a.aspect())
		p(k + "norm", a.normalized()); p(k + "isn", a.is_normalized()); p(k + "zap", a.is_zero_approx()); p(k + "fin", a.is_finite())
		p(k + "abs", a.abs()); p(k + "ceil", a.ceil()); p(k + "floor", a.floor()); p(k + "round", a.round()); p(k + "sign", a.sign())
		p(k + "orth", a.orthogonal()); p(k + "rot", a.rotated(0.3)); p(k + "rot2", a.rotated(-2.0)); p(k + "lim", a.limit_length(1.5)); p(k + "lim1", a.limit_length())
		p(k + "clampf", a.clampf(-1, 1)); p(k + "clamp", a.clamp(Vector2(-0.5, -0.5), Vector2(0.5, 2))); p(k + "snap", a.snapped(Vector2(0.25, 0.1)))
		p(k + "snapf", a.snappedf(0.3)); p(k + "posmod", a.posmod(0.7)); p(k + "posmodv", a.posmodv(Vector2(0.3, -0.4)))
		p(k + "maxi", a.max_axis_index()); p(k + "mini", a.min_axis_index()); p(k + "minf", a.minf(0.5)); p(k + "maxf", a.maxf(0.5))
		p(k + "neg", -a); p(k + "pos", +a); p(k + "m2", a * 2); p(k + "m25", a * 2.5); p(k + "lm25", 2.5 * a); p(k + "d3", a / 3.0); p(k + "di3", a / 3)
		p(k + "hash", hash(a)); p(k + "fromang", Vector2.from_angle(a.x))
		for j in V2.size():
			var b: Vector2 = V2[j]
			var n := b.normalized()
			var kk := k + "%d." % j
			p(kk + "dot", a.dot(b)); p(kk + "cross", a.cross(b)); p(kk + "dist", a.distance_to(b)); p(kk + "dsq", a.distance_squared_to(b))
			p(kk + "angto", a.angle_to(b)); p(kk + "angpt", a.angle_to_point(b)); p(kk + "dir", a.direction_to(b)); p(kk + "lerp", a.lerp(b, 0.3))
			p(kk + "slerp", a.slerp(b, 0.3)); p(kk + "slerp3", a.slerp(b, 1.0 / 3.0)); p(kk + "mt", a.move_toward(b, 0.5)); p(kk + "proj", a.project(b))
			p(kk + "min", a.min(b)); p(kk + "max", a.max(b)); p(kk + "mul", a * b); p(kk + "div", a / b); p(kk + "add", a + b); p(kk + "sub", a - b)
			p(kk + "iea", a.is_equal_approx(b)); p(kk + "lt", a < b); p(kk + "le", a <= b); p(kk + "eq", a == b)
			p(kk + "cub", a.cubic_interpolate(b, V2[(j + 1) % V2.size()], V2[(j + 2) % V2.size()], 0.4))
			p(kk + "cubt", a.cubic_interpolate_in_time(b, V2[(j + 1) % V2.size()], V2[(j + 2) % V2.size()], 0.4, 1.0, -0.5, 2.0))
			p(kk + "bez", a.bezier_interpolate(V2[(j + 3) % V2.size()], V2[(j + 5) % V2.size()], b, 0.3))
			p(kk + "bezd", a.bezier_derivative(V2[(j + 3) % V2.size()], V2[(j + 5) % V2.size()], b, 0.3))
			p(kk + "slide", a.slide(n)); p(kk + "refl", a.reflect(n)); p(kk + "bnc", a.bounce(n))

func vec2i_cases() -> void:
	var VI := [Vector2i(0, 0), Vector2i(3, -4), Vector2i(-7, 2), Vector2i(5, 5), Vector2i(1, 0), Vector2i(-2147483648, 7)]
	for i in VI.size():
		var a: Vector2i = VI[i]
		var k := "v2i.%d." % i
		p(k + "len", a.length()); p(k + "lsq", a.length_squared()); p(k + "asp", a.aspect()); p(k + "abs", a.abs()); p(k + "sign", a.sign())
		p(k + "clamp", a.clamp(Vector2i(-3, -3), Vector2i(4, 1))); p(k + "clampi", a.clampi(-2, 3)); p(k + "snap", a.snapped(Vector2i(3, 2))); p(k + "snapi", a.snappedi(4))
		p(k + "mini", a.mini(1)); p(k + "maxi", a.maxi(1)); p(k + "maxax", a.max_axis_index()); p(k + "minax", a.min_axis_index())
		p(k + "neg", -a); p(k + "m3", a * 3); p(k + "m25", a * 2.5); p(k + "lm3", 3 * a); p(k + "d2", a / 2); p(k + "mod3", a % 3); p(k + "df", a / 2.0)
		p(k + "hash", hash(a)); p(k + "tov2", Vector2(a)); p(k + "fromv2", Vector2i(Vector2(a) * 0.7))
		for j in VI.size():
			var b: Vector2i = VI[j]
			var kk := k + "%d." % j
			p(kk + "add", a + b); p(kk + "sub", a - b); p(kk + "mul", a * b); p(kk + "min", a.min(b)); p(kk + "max", a.max(b))
			p(kk + "dist", a.distance_to(b)); p(kk + "dsq", a.distance_squared_to(b)); p(kk + "lt", a < b)
			if b.x != 0 and b.y != 0:
				p(kk + "div", a / b); p(kk + "mod", a % b)

func vec3_cases() -> void:
	for i in V3.size():
		var a: Vector3 = V3[i]
		var k := "v3.%d." % i
		p(k + "str", a); p(k + "len", a.length()); p(k + "lsq", a.length_squared()); p(k + "norm", a.normalized()); p(k + "isn", a.is_normalized())
		p(k + "zap", a.is_zero_approx()); p(k + "fin", a.is_finite()); p(k + "inv", a.inverse()); p(k + "abs", a.abs()); p(k + "ceil", a.ceil())
		p(k + "floor", a.floor()); p(k + "round", a.round()); p(k + "sign", a.sign()); p(k + "lim", a.limit_length(1.5)); p(k + "lim1", a.limit_length())
		p(k + "clampf", a.clampf(-1, 1)); p(k + "clamp", a.clamp(Vector3(-0.5, -0.5, 0), Vector3(0.5, 2, 1))); p(k + "snap", a.snapped(Vector3(0.25, 0.1, 2)))
		p(k + "snapf", a.snappedf(0.3)); p(k + "posmod", a.posmod(0.7)); p(k + "posmodv", a.posmodv(Vector3(0.3, -0.4, 5)))
		p(k + "maxi", a.max_axis_index()); p(k + "mini", a.min_axis_index()); p(k + "minf", a.minf(0.5)); p(k + "maxf", a.maxf(0.5))
		p(k + "neg", -a); p(k + "pos", +a); p(k + "m2", a * 2); p(k + "m25", a * 2.5); p(k + "lm25", 2.5 * a); p(k + "d3", a / 3.0); p(k + "di3", a / 3)
		p(k + "hash", hash(a)); p(k + "oct", a.octahedron_encode()); p(k + "octd", Vector3.octahedron_decode(a.octahedron_encode()))
		p(k + "octd2", Vector3.octahedron_decode(Vector2(a.x, a.y)))
		for ax in [Vector3(0, 1, 0), Vector3(1, 2, 3).normalized(), Vector3(1, 1, 0)]:
			p(k + "rotax", a.rotated(ax, 0.7))
		for j in V3.size():
			var b: Vector3 = V3[j]
			var n := b.normalized()
			var kk := k + "%d." % j
			p(kk + "dot", a.dot(b)); p(kk + "cross", a.cross(b)); p(kk + "dist", a.distance_to(b)); p(kk + "dsq", a.distance_squared_to(b))
			p(kk + "angto", a.angle_to(b)); p(kk + "sang", a.signed_angle_to(b, Vector3(0, 1, 0))); p(kk + "dir", a.direction_to(b))
			p(kk + "lerp", a.lerp(b, 0.3)); p(kk + "slerp", a.slerp(b, 0.3)); p(kk + "slerp3", a.slerp(b, 1.0 / 3.0)); p(kk + "mt", a.move_toward(b, 0.5))
			p(kk + "proj", a.project(b)); p(kk + "min", a.min(b)); p(kk + "max", a.max(b)); p(kk + "mul", a * b); p(kk + "div", a / b)
			p(kk + "add", a + b); p(kk + "sub", a - b); p(kk + "iea", a.is_equal_approx(b)); p(kk + "lt", a < b); p(kk + "le", a <= b); p(kk + "eq", a == b)
			p(kk + "outer", a.outer(b))
			p(kk + "cub", a.cubic_interpolate(b, V3[(j + 1) % V3.size()], V3[(j + 2) % V3.size()], 0.4))
			p(kk + "cubt", a.cubic_interpolate_in_time(b, V3[(j + 1) % V3.size()], V3[(j + 2) % V3.size()], 0.4, 1.0, -0.5, 2.0))
			p(kk + "bez", a.bezier_interpolate(V3[(j + 3) % V3.size()], V3[(j + 5) % V3.size()], b, 0.3))
			p(kk + "bezd", a.bezier_derivative(V3[(j + 3) % V3.size()], V3[(j + 5) % V3.size()], b, 0.3))
			p(kk + "slide", a.slide(n)); p(kk + "refl", a.reflect(n)); p(kk + "bnc", a.bounce(n))

func vec34i_cases() -> void:
	var VI := [Vector3i(0, 0, 0), Vector3i(3, -4, 5), Vector3i(-7, 2, -1), Vector3i(5, 5, 5), Vector3i(1, 0, 2)]
	for i in VI.size():
		var a: Vector3i = VI[i]
		var k := "v3i.%d." % i
		p(k + "str", a); p(k + "len", a.length()); p(k + "lsq", a.length_squared()); p(k + "abs", a.abs()); p(k + "sign", a.sign())
		p(k + "clamp", a.clamp(Vector3i(-3, -3, -3), Vector3i(4, 1, 2))); p(k + "clampi", a.clampi(-2, 3)); p(k + "snap", a.snapped(Vector3i(3, 2, 4))); p(k + "snapi", a.snappedi(4))
		p(k + "mini", a.mini(1)); p(k + "maxi", a.maxi(1)); p(k + "maxax", a.max_axis_index()); p(k + "minax", a.min_axis_index())
		p(k + "neg", -a); p(k + "m3", a * 3); p(k + "m25", a * 2.5); p(k + "lm3", 3 * a); p(k + "lm25", 2.5 * a); p(k + "d2", a / 2); p(k + "mod3", a % 3); p(k + "df", a / 2.0)
		p(k + "hash", hash(a)); p(k + "tov3", Vector3(a)); p(k + "fromv3", Vector3i(Vector3(a) * 0.7)); p(k + "type", typeof(a))
		for j in VI.size():
			var b: Vector3i = VI[j]
			var kk := k + "%d." % j
			p(kk + "add", a + b); p(kk + "sub", a - b); p(kk + "mul", a * b); p(kk + "min", a.min(b)); p(kk + "max", a.max(b))
			p(kk + "dist", a.distance_to(b)); p(kk + "dsq", a.distance_squared_to(b)); p(kk + "lt", a < b); p(kk + "eq", a == b)
			if b.x != 0 and b.y != 0 and b.z != 0:
				p(kk + "div", a / b); p(kk + "mod", a % b)
	var V4 := [Vector4(0, 0, 0, 0), Vector4(1, -2, 3.5, 0.25), Vector4(0.1, 0.2, 0.3, 0.4), Vector4(-1, -1, 2, 2), Vector4(1e-6, 0, 0, -1e-6)]
	for i in V4.size():
		var a: Vector4 = V4[i]
		var k := "v4.%d." % i
		p(k + "str", a); p(k + "len", a.length()); p(k + "lsq", a.length_squared()); p(k + "norm", a.normalized()); p(k + "isn", a.is_normalized())
		p(k + "abs", a.abs()); p(k + "sign", a.sign()); p(k + "floor", a.floor()); p(k + "ceil", a.ceil()); p(k + "round", a.round()); p(k + "inv", a.inverse())
		p(k + "maxax", a.max_axis_index()); p(k + "minax", a.min_axis_index()); p(k + "snapf", a.snappedf(0.3)); p(k + "posmod", a.posmod(0.7))
		p(k + "clampf", a.clampf(-1, 1)); p(k + "neg", -a); p(k + "m25", a * 2.5); p(k + "lm2", 2 * a); p(k + "d3", a / 3.0); p(k + "hash", hash(a)); p(k + "zap", a.is_zero_approx())
		p(k + "minf", a.minf(0.2)); p(k + "maxf", a.maxf(0.2))
		for j in V4.size():
			var b: Vector4 = V4[j]
			var kk := k + "%d." % j
			p(kk + "dot", a.dot(b)); p(kk + "dist", a.distance_to(b)); p(kk + "dir", a.direction_to(b)); p(kk + "lerp", a.lerp(b, 0.3))
			p(kk + "cub", a.cubic_interpolate(b, V4[(j + 1) % V4.size()], V4[(j + 2) % V4.size()], 0.4))
			p(kk + "cubt", a.cubic_interpolate_in_time(b, V4[(j + 1) % V4.size()], V4[(j + 2) % V4.size()], 0.4, 1.0, -0.5, 2.0))
			p(kk + "add", a + b); p(kk + "mul", a * b); p(kk + "div", a / b); p(kk + "lt", a < b); p(kk + "posmodv", a.posmodv(b)); p(kk + "snap", a.snapped(b))
			p(kk + "clamp", a.clamp(b, b + Vector4(1, 1, 1, 1))); p(kk + "min", a.min(b)); p(kk + "max", a.max(b)); p(kk + "iea", a.is_equal_approx(b))
	var V4I := [Vector4i(0, 0, 0, 0), Vector4i(1, -2, 3, 4), Vector4i(-5, 6, -7, 8)]
	for i in V4I.size():
		var a: Vector4i = V4I[i]
		var k := "v4i.%d." % i
		p(k + "str", a); p(k + "len", a.length()); p(k + "abs", a.abs()); p(k + "sign", a.sign()); p(k + "m25", a * 2.5); p(k + "m3", a * 3); p(k + "lm3", 3 * a)
		p(k + "hash", hash(a)); p(k + "maxax", a.max_axis_index()); p(k + "minax", a.min_axis_index()); p(k + "snapi", a.snappedi(3)); p(k + "clampi", a.clampi(-3, 3))
		for j in V4I.size():
			var b: Vector4i = V4I[j]
			p(k + "%d.add" % j, a + b); p(k + "%d.mul" % j, a * b); p(k + "%d.lt" % j, a < b); p(k + "%d.dsq" % j, a.distance_squared_to(b))

func make_bases() -> Array:
	var B := [Basis(), Basis.FLIP_X, Basis.from_scale(Vector3(2, -1, 0.5)), Basis(Vector3(1, 2, 3), Vector3(4, 5, 6), Vector3(7, 8, 10)),
		Basis(Vector3(1, 2, 3), Vector3(2, 4, 6), Vector3(0, 0, 1)), Basis(Vector3(0, 1, 0), 0.7), Basis(Vector3(1, 2, 3).normalized(), -2.1),
		Basis(Vector3(1, 1, 0), 0.5), Basis(Quaternion(0.1, 0.2, 0.3, 0.9)), Basis.from_scale(Vector3(1.5, 1.5, 1.5)) * Basis.from_euler(Vector3(0.3, -0.2, 1.1))]
	for e in EUL:
		B.append(Basis.from_euler(e))
	B.append(Basis.from_euler(Vector3(0.4, 0.5, 0.6), EULER_ORDER_ZXY) * Basis.from_scale(Vector3(-1, 2, 3)))
	return B

func basis_cases() -> void:
	for e in EUL.size():
		for o in 6:
			var b := Basis.from_euler(EUL[e], o)
			var k := "be.%d.%d." % [e, o]
			p(k + "b", b)
			for o2 in 6:
				p(k + "ge%d" % o2, b.get_euler(o2))
	var B := make_bases()
	for i in B.size():
		var b: Basis = B[i]
		var k := "b.%d." % i
		p(k + "str", b); p(k + "det", b.determinant()); p(k + "inv", b.inverse()); p(k + "tr", b.transposed()); p(k + "orth", b.orthonormalized())
		p(k + "scale", b.get_scale()); p(k + "rq", b.get_rotation_quaternion()); p(k + "ion", b.is_orthonormal()); p(k + "icf", b.is_conformal())
		p(k + "fin", b.is_finite()); p(k + "hash", hash(b)); p(k + "q", Quaternion(b)); p(k + "x", b.x); p(k + "y", b.y); p(k + "z", b.z); p(k + "i2", b[2])
		p(k + "m2", b * 2.0); p(k + "d2", b / 2.0); p(k + "mi3", b * 3)
		for o in 6:
			p(k + "ge%d" % o, b.get_euler(o))
		for v in [Vector3(1, 2, 3), Vector3(-0.5, 0.25, 2)]:
			p(k + "tdx", b.tdotx(v)); p(k + "tdy", b.tdoty(v)); p(k + "tdz", b.tdotz(v)); p(k + "sc", b.scaled(v)); p(k + "scl", b.scaled_local(v))
			p(k + "xf", b * v); p(k + "xfi", v * b)
		p(k + "rot", b.rotated(Vector3(1, 2, 3).normalized(), 0.7)); p(k + "rotbad", b.rotated(Vector3(1, 2, 3), 0.7))
		for j in range(i % 3, B.size(), 3):
			var c: Basis = B[j]
			p(k + "%d.mul" % j, b * c); p(k + "%d.iea" % j, b.is_equal_approx(c)); p(k + "%d.eq" % j, b == c)
			p(k + "%d.slerp" % j, b.slerp(c, 0.3))
	for t in [Vector3(0, 0, -1), Vector3(1, 2, 3), Vector3(0, 5, 0), Vector3(0, -2, 0), Vector3(1e-7, 0, 0), Vector3(-3, 0.5, 4)]:
		for up in [Vector3.UP, Vector3(0, 0, 1), Vector3(1, 1, 1)]:
			p("blook.%s.%s" % [t, up], Basis.looking_at(t, up)); p("blookm.%s.%s" % [t, up], Basis.looking_at(t, up, true))
	p("blook.def", Basis.looking_at(Vector3(3, -1, 2)))
	p("bconst", [Basis.IDENTITY, Basis.FLIP_Y, Basis.FLIP_Z])

func make_quats() -> Array:
	var Q := [Quaternion(), Quaternion(Vector3(0, 1, 0), 0.5), Quaternion(Vector3(1, 2, 3).normalized(), 2.5), Quaternion(0.1, 0.2, 0.3, 0.9),
		Quaternion(0.1, 0.2, 0.3, 0.9).normalized(), Quaternion(Vector3(0, 1, 0), PI), Quaternion(Vector3(0, 1, 0), 0.5 + 1e-6),
		-Quaternion(Vector3(0, 1, 0), 0.5), Quaternion(Vector3(1, 0, 0), -3.0), Quaternion(0, 0, 0, 0)]
	for e in EUL:
		Q.append(Quaternion.from_euler(e))
	return Q

func quat_cases() -> void:
	var Q := make_quats()
	for i in Q.size():
		var q: Quaternion = Q[i]
		var k := "q.%d." % i
		p(k + "str", q); p(k + "len", q.length()); p(k + "lsq", q.length_squared()); p(k + "norm", q.normalized()); p(k + "isn", q.is_normalized())
		p(k + "inv", q.inverse()); p(k + "log", q.log()); p(k + "exp", q.exp()); p(k + "axis", q.get_axis()); p(k + "angle", q.get_angle())
		p(k + "fin", q.is_finite()); p(k + "hash", hash(q)); p(k + "b", Basis(q)); p(k + "neg", -q); p(k + "m2", q * 2.0); p(k + "d2", q / 2.0)
		p(k + "lm2", 2.0 * q); p(k + "mi2", q * 2); p(k + "di2", q / 2)
		for o in 6:
			p(k + "ge%d" % o, q.get_euler(o))
		for v in [Vector3(1, 2, 3), Vector3(-0.5, 0.25, 2)]:
			p(k + "xf", q * v); p(k + "xfi", v * q)
		for j in range(i % 2, Q.size(), 2):
			var r: Quaternion = Q[j]
			var kk := k + "%d." % j
			p(kk + "mul", q * r); p(kk + "add", q + r); p(kk + "sub", q - r); p(kk + "dot", q.dot(r)); p(kk + "angto", q.angle_to(r))
			p(kk + "slerp", q.slerp(r, 0.3)); p(kk + "slerpni", q.slerpni(r, 0.3)); p(kk + "iea", q.is_equal_approx(r)); p(kk + "eq", q == r)
			p(kk + "sci", q.spherical_cubic_interpolate(r, Q[(j + 1) % Q.size()], Q[(j + 2) % Q.size()], 0.3))
			p(kk + "scit", q.spherical_cubic_interpolate_in_time(r, Q[(j + 1) % Q.size()], Q[(j + 2) % Q.size()], 0.3, 1.0, -0.5, 2.0))
	for a in [Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(1, 2, 3), Vector3(-1, 0, 0), Vector3(-1, 1e-8, 0), Vector3(0.3, -0.2, 0.9), Vector3(0, 0, 0)]:
		for b in [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(-2, -4, -6), Vector3(0.1, 0.1, -0.9)]:
			p("qarc.%s.%s" % [a, b], Quaternion(a, b))
	for ang in [0.0, 0.3, -1.7, PI, 2 * PI, 10.0]:
		p("qaa.%s" % ang, Quaternion(Vector3(0, 0, 1), ang)); p("qaa2.%s" % ang, Quaternion(Vector3(1, -2, 2).normalized(), ang))
	p("qaabad", Quaternion(Vector3(1, 1, 0), 0.5))
	var q0 := Quaternion(Vector3(0, 1, 0), 0.1)
	for d in [0.0, 1e-7, 1e-5, 1e-3]:
		p("qslerp0.%s" % d, q0.slerp(Quaternion(Vector3(0, 1, 0), 0.1 + d), 0.5)); p("qslerp180.%s" % d, q0.slerp(-Quaternion(Vector3(0, 1, 0), 0.1 + d), 0.5))
		p("qslerpPI.%s" % d, q0.slerp(Quaternion(Vector3(0, 1, 0), 0.1 + PI + d), 0.5)); p("qslerpni0.%s" % d, q0.slerpni(Quaternion(Vector3(0, 1, 0), 0.1 + d), 0.5))

func make_xforms() -> Array:
	var B := make_bases()
	var T := [Transform3D(), Transform3D.FLIP_X, Transform3D(Basis(), Vector3(1, 2, 3)), Transform3D(B[6], Vector3(-4, 0.5, 2)),
		Transform3D(B[2], Vector3(0.1, 0.2, 0.3)), Transform3D(B[3], Vector3(5, -5, 5)), Transform3D(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0), Vector3(7, 8, 9)),
		Transform3D(B[9], Vector3(-1, -2, -3)), Transform3D(B[14], Vector3(0, 10, -20))]
	return T

func xform3_cases() -> void:
	var T := make_xforms()
	var A := [AABB(Vector3(0, 0, 0), Vector3(1, 1, 1)), AABB(Vector3(-1, 2, -3), Vector3(2, 0.5, 4))]
	var P := [Plane(Vector3(0, 1, 0), 2), Plane(Vector3(1, 2, 3).normalized(), -1.5)]
	for i in T.size():
		var t: Transform3D = T[i]
		var k := "t.%d." % i
		p(k + "str", t); p(k + "inv", t.inverse()); p(k + "ainv", t.affine_inverse()); p(k + "orth", t.orthonormalized())
		p(k + "rot", t.rotated(Vector3(0, 1, 0), 0.9)); p(k + "rotl", t.rotated_local(Vector3(1, 2, 3).normalized(), -0.4)); p(k + "sc", t.scaled(Vector3(2, -1, 0.5)))
		p(k + "scl", t.scaled_local(Vector3(2, -1, 0.5))); p(k + "tr", t.translated(Vector3(1, -2, 3))); p(k + "trl", t.translated_local(Vector3(1, -2, 3)))
		p(k + "look", t.looking_at(Vector3(3, 4, -5))); p(k + "lookm", t.looking_at(Vector3(3, 4, -5), Vector3(0, 0, 1), true)); p(k + "lookbad", t.looking_at(t.origin))
		p(k + "hash", hash(t)); p(k + "fin", t.is_finite()); p(k + "m2", t * 2.0); p(k + "d2", t / 2.0); p(k + "basis", t.basis); p(k + "origin", t.origin)
		for v in [Vector3(1, 2, 3), Vector3(-0.5, 0.25, 2)]:
			p(k + "xf", t * v); p(k + "xfi", v * t)
		for a in A:
			p(k + "xa", t * a); p(k + "xai", a * t)
		for pl in P:
			p(k + "xp", t * pl); p(k + "xpi", pl * t)
		for j in T.size():
			var u: Transform3D = T[j]
			p(k + "%d.mul" % j, t * u); p(k + "%d.iea" % j, t.is_equal_approx(u)); p(k + "%d.interp" % j, t.interpolate_with(u, 0.3))

func aabb_cases() -> void:
	var A := [AABB(), AABB(Vector3(0, 0, 0), Vector3(1, 1, 1)), AABB(Vector3(-1, 2, -3), Vector3(2, 0.5, 4)), AABB(Vector3(0.5, 0.5, 0.5), Vector3(2, 2, 2)),
		AABB(Vector3(1, 1, 1), Vector3(-2, 3, -0.5)), AABB(Vector3(0, 0, 0), Vector3(3, 0, 1)), AABB(Vector3(0.1, 0.2, 0.3), Vector3(0.4, 0.5, 0.6))]
	var PTS := [Vector3(0, 0, 0), Vector3(0.5, 0.5, 0.5), Vector3(1, 1, 1), Vector3(-2, 1, 0), Vector3(0.2, 2.25, -1)]
	for i in A.size():
		var a: AABB = A[i]
		var k := "a.%d." % i
		p(k + "str", a); p(k + "abs", a.abs()); p(k + "ctr", a.get_center()); p(k + "vol", a.get_volume()); p(k + "hv", a.has_volume()); p(k + "hs", a.has_surface())
		p(k + "grow", a.grow(0.5)); p(k + "end", a.end); p(k + "hash", hash(a)); p(k + "fin", a.is_finite())
		p(k + "la", a.get_longest_axis()); p(k + "lai", a.get_longest_axis_index()); p(k + "las", a.get_longest_axis_size())
		p(k + "sa", a.get_shortest_axis()); p(k + "sai", a.get_shortest_axis_index()); p(k + "sas", a.get_shortest_axis_size())
		for e in 8:
			p(k + "ep%d" % e, a.get_endpoint(e))
		for v in PTS:
			p(k + "hp", a.has_point(v)); p(k + "exp", a.expand(v)); p(k + "sup", a.get_support(v - Vector3(0.5, 0.5, 0.5)))
		for r in [[Vector3(-5, 0.5, 0.5), Vector3(1, 0, 0)], [Vector3(0.5, 0.5, 0.5), Vector3(0, 1, 0)], [Vector3(-5, -5, -5), Vector3(1, 1, 1)],
				[Vector3(-5, 0.5, 0.5), Vector3(0, 1, 0)], [Vector3(3, 3, 3), Vector3(-1, -1.2, -0.9)], [Vector3(0.2, 2.1, -2), Vector3(0.1, 0, 1)]]:
			p(k + "ray", a.intersects_ray(r[0], r[1])); p(k + "seg", a.intersects_segment(r[0], r[0] + r[1] * 10))
		for pl in [Plane(Vector3(0, 1, 0), 0.5), Plane(Vector3(1, 1, 1).normalized(), 10), Plane(Vector3(1, 0, 0), -1)]:
			p(k + "ip", a.intersects_plane(pl))
		for j in A.size():
			var b: AABB = A[j]
			var kk := k + "%d." % j
			p(kk + "int", a.intersects(b)); p(kk + "enc", a.encloses(b)); p(kk + "isect", a.intersection(b)); p(kk + "merge", a.merge(b))
			p(kk + "iea", a.is_equal_approx(b)); p(kk + "eq", a == b)

func plane_cases() -> void:
	var P := [Plane(), Plane(Vector3(0, 1, 0), 2), Plane(Vector3(1, 2, 3).normalized(), -1.5), Plane(Vector3(1, 2, 3), 4), Plane(1, 0, 0, 0.25),
		Plane(Vector3(0, 0, 1), Vector3(1, 2, 3)), Plane(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)), Plane(Vector3(1, 2, 3), Vector3(-1, 0.5, 2), Vector3(4, -4, 0.1)),
		Plane(Vector3(0.6, 0.8, 0)), Plane.PLANE_XZ]
	var PTS := [Vector3(0, 0, 0), Vector3(1, 2, 3), Vector3(0, 2, 0), Vector3(-4, 0.5, 9)]
	for i in P.size():
		var pl: Plane = P[i]
		var k := "p.%d." % i
		p(k + "str", pl); p(k + "norm", pl.normalized()); p(k + "ctr", pl.get_center()); p(k + "neg", -pl); p(k + "hash", hash(pl))
		p(k + "xyzd", [pl.x, pl.y, pl.z, pl.d]); p(k + "fin", pl.is_finite())
		for v in PTS:
			p(k + "dist", pl.distance_to(v)); p(k + "over", pl.is_point_over(v)); p(k + "has", pl.has_point(v)); p(k + "has2", pl.has_point(v, 0.5)); p(k + "proj", pl.project(v))
			p(k + "ray", pl.intersects_ray(v, Vector3(0, -1, 0))); p(k + "ray2", pl.intersects_ray(v, Vector3(0.3, 0.4, -0.5)))
			p(k + "seg", pl.intersects_segment(v, v + Vector3(0, -5, 1)))
		for j in P.size():
			p(k + "%d.i3" % j, pl.intersect_3(P[j], P[(j + 3) % P.size()])); p(k + "%d.iea" % j, pl.is_equal_approx(P[j])); p(k + "%d.eq" % j, pl == P[j])

func make_projections() -> Array:
	return [Projection(), Projection.create_perspective(70, 16.0 / 9.0, 0.05, 4000), Projection.create_perspective(70, 16.0 / 9.0, 0.05, 4000, true),
		Projection.create_perspective(45, 0.5, 0.1, 100), Projection.create_perspective(45, 0.5, 0.1, 100, true), Projection.create_perspective(90, 1, 1, 10),
		Projection.create_orthogonal(-1, 1, -0.5, 0.5, 0.1, 100), Projection.create_orthogonal_aspect(10, 16.0 / 9.0, 0.1, 50),
		Projection.create_orthogonal_aspect(10, 16.0 / 9.0, 0.1, 50, true), Projection.create_frustum(-0.3, 0.5, -0.2, 0.25, 0.1, 30),
		Projection.create_frustum_aspect(1.5, 4.0 / 3.0, Vector2(0.1, -0.2), 0.5, 80), Projection.create_frustum_aspect(1.5, 4.0 / 3.0, Vector2(0.1, -0.2), 0.5, 80, true),
		Projection.create_frustum(1, -1, 0, 1, 0.1, 10), Projection.create_fit_aabb(AABB(Vector3(-1, -2, -3), Vector3(2, 4, 6))),
		Projection.create_depth_correction(true), Projection.create_perspective(60, 1.25, 0.1, 0.1),
		Projection(Vector4(1, 2, 3, 4), Vector4(0, 1, 0.5, -1), Vector4(2, 0, 1, 0), Vector4(0.25, 0.5, 0, 1)),
		Projection(Transform3D(Basis.from_euler(Vector3(0.1, 0.2, 0.3)), Vector3(1, 2, 3)))]

func projection_cases() -> void:
	var PR := make_projections()
	var cam := Transform3D(Basis.from_euler(Vector3(-0.4, 0.8, 0)), Vector3(3, 10, 12))
	for i in PR.size():
		var pr: Projection = PR[i]
		var k := "pr.%d." % i
		p(k + "str", pr); p(k + "det", pr.determinant()); p(k + "inv", pr.inverse()); p(k + "zf", pr.get_z_far()); p(k + "zn", pr.get_z_near())
		p(k + "asp", pr.get_aspect()); p(k + "fov", pr.get_fov()); p(k + "orth", pr.is_orthogonal()); p(k + "vhe", pr.get_viewport_half_extents())
		p(k + "fhe", pr.get_far_plane_half_extents()); p(k + "lod", pr.get_lod_multiplier()); p(k + "ppm", pr.get_pixels_per_meter(1024)); p(k + "hash", hash(pr))
		p(k + "zadj", pr.perspective_znear_adjusted(0.5)); p(k + "fy", pr.flipped_y()); p(k + "jit", pr.jitter_offseted(Vector2(0.01, -0.02))); p(k + "xf3", Transform3D(pr))
		p(k + "cols", [pr.x, pr.y, pr.z, pr.w, pr[3]])
		for pi in 6:
			p(k + "pl%d" % pi, pr.get_projection_plane(pi)); p(k + "cpl%d" % pi, cam * pr.get_projection_plane(pi))
		for v in [Vector4(1, 2, 3, 1), Vector4(-0.5, 0.25, -10, 1), Vector4(0, 0, 0, 0)]:
			p(k + "xf", pr * v); p(k + "xfi", v * pr)
		for j in range(i % 2, PR.size(), 2):
			p(k + "%d.mul" % j, pr * PR[j])
	for f in [[70.0, 16.0 / 9.0], [45.0, 0.75], [90.0, 1.0], [110.0, 2.5]]:
		p("prfovy.%s" % f[0], Projection.get_fovy(f[0], f[1]))

func make_x2() -> Array:
	return [Transform2D(), Transform2D.FLIP_X, Transform2D(0.5, Vector2(1, 2)), Transform2D(0.1, Vector2(-3, 4)), Transform2D(-2.0, Vector2(2, -1.5), 0.3, Vector2(5, 6)),
		Transform2D(PI / 6, Vector2(1, 1), 0, Vector2(0, 0)), Transform2D(Vector2(1, 2), Vector2(3, 4), Vector2(5, 6)), Transform2D(Vector2(1, 2), Vector2(2, 4), Vector2(1, 1)),
		Transform2D(1.0, Vector2(-1, 2), -0.2, Vector2(0.5, 0.25))]

func xform2_cases() -> void:
	var X := make_x2()
	var R := [Rect2(0, 0, 1, 1), Rect2(-1, 2, 3, 0.5)]
	for i in X.size():
		var t: Transform2D = X[i]
		var k := "x2.%d." % i
		p(k + "str", t); p(k + "inv", t.inverse()); p(k + "ainv", t.affine_inverse()); p(k + "rot", t.get_rotation()); p(k + "org", t.get_origin())
		p(k + "scale", t.get_scale()); p(k + "skew", t.get_skew()); p(k + "orth", t.orthonormalized()); p(k + "rotd", t.rotated(0.7)); p(k + "rotl", t.rotated_local(-0.3))
		p(k + "sc", t.scaled(Vector2(2, -0.5))); p(k + "scl", t.scaled_local(Vector2(2, -0.5))); p(k + "tr", t.translated(Vector2(1, -2))); p(k + "trl", t.translated_local(Vector2(1, -2)))
		p(k + "det", t.determinant()); p(k + "conf", t.is_conformal()); p(k + "fin", t.is_finite()); p(k + "hash", hash(t)); p(k + "look", t.looking_at(Vector2(3, -4)))
		p(k + "look0", t.looking_at()); p(k + "m2", t * 2.0); p(k + "d2", t / 2.0); p(k + "cols", [t.x, t.y, t.origin, t[1]])
		for v in [Vector2(1, 2), Vector2(-0.5, 0.25)]:
			p(k + "bx", t.basis_xform(v)); p(k + "bxi", t.basis_xform_inv(v)); p(k + "xf", t * v); p(k + "xfi", v * t)
		for r in R:
			p(k + "xr", t * r); p(k + "xri", r * t)
		for j in X.size():
			var u: Transform2D = X[j]
			p(k + "%d.mul" % j, t * u); p(k + "%d.iea" % j, t.is_equal_approx(u)); p(k + "%d.interp" % j, t.interpolate_with(u, 0.3))

func rect2_cases() -> void:
	var R := [Rect2(), Rect2(0, 0, 1, 1), Rect2(-1, 2, 3, 0.5), Rect2(0.5, 0.5, 2, 2), Rect2(1, 1, -2, 3), Rect2(0.1, 0.2, 0.3, 0.7), Rect2(1, 0, 0, 5)]
	var PTS := [Vector2(0, 0), Vector2(0.5, 0.5), Vector2(1, 1), Vector2(-2, 1), Vector2(0.2, 2.25)]
	for i in R.size():
		var r: Rect2 = R[i]
		var k := "r.%d." % i
		p(k + "str", r); p(k + "abs", r.abs()); p(k + "area", r.get_area()); p(k + "ctr", r.get_center()); p(k + "ha", r.has_area()); p(k + "end", r.end)
		p(k + "grow", r.grow(0.5)); p(k + "gi", r.grow_individual(0.1, 0.2, 0.3, 0.4)); p(k + "hash", hash(r)); p(k + "fin", r.is_finite())
		for s in 4:
			p(k + "gs%d" % s, r.grow_side(s, 0.7))
		for v in PTS:
			p(k + "hp", r.has_point(v)); p(k + "exp", r.expand(v)); p(k + "sup", r.get_support(v - Vector2(0.5, 0.5)))
		for j in R.size():
			var o: Rect2 = R[j]
			var kk := k + "%d." % j
			p(kk + "int", r.intersects(o)); p(kk + "intb", r.intersects(o, true)); p(kk + "enc", r.encloses(o)); p(kk + "isect", r.intersection(o))
			p(kk + "merge", r.merge(o)); p(kk + "iea", r.is_equal_approx(o)); p(kk + "eq", r == o)

func color_cases() -> void:
	var C := [Color(), Color(1, 0.5, 0.25), Color(0.1, 0.2, 0.3, 0.4), Color(2, -0.5, 0.5, 1.5), Color(0.333333, 0.666667, 0.999), Color(0, 0, 0, 0),
		Color(1, 1, 1), Color(0.5 / 255.0, 2.5 / 255.0, 127.5 / 255.0, 0.5), Color.ALICE_BLUE, Color.REBECCA_PURPLE, Color.hex(0x7FFFD4FF), Color(0.02, 0.9, 0.6)]
	for i in C.size():
		var c: Color = C[i]
		var k := "c.%d." % i
		p(k + "str", c); p(k + "html", c.to_html()); p(k + "html3", c.to_html(false)); p(k + "rgba32", c.to_rgba32()); p(k + "argb32", c.to_argb32())
		p(k + "abgr32", c.to_abgr32()); p(k + "rgba64", c.to_rgba64()); p(k + "argb64", c.to_argb64()); p(k + "abgr64", c.to_abgr64())
		p(k + "hsv", [c.h, c.s, c.v]); p(k + "c8", [c.r8, c.g8, c.b8, c.a8]); p(k + "lum", c.get_luminance()); p(k + "inv", c.inverted())
		p(k + "light", c.lightened(0.3)); p(k + "dark", c.darkened(0.3)); p(k + "clamp", c.clamp()); p(k + "clamp2", c.clamp(Color(0.2, 0.2, 0.2, 0.2), Color(0.6, 0.7, 0.8, 0.9)))
		p(k + "s2l", c.srgb_to_linear()); p(k + "l2s", c.linear_to_srgb()); p(k + "ok", [c.ok_hsl_h, c.ok_hsl_s, c.ok_hsl_l]); p(k + "neg", -c)
		p(k + "m2", c * 2.0); p(k + "d2", c / 2.0); p(k + "lm2", 2.0 * c); p(k + "mi3", c * 3); p(k + "hash", hash(c))
		p(k + "fhsv", Color.from_hsv(c.r, c.g, c.b, c.a)); p(k + "fok", Color.from_ok_hsl(c.r, c.g, c.b, c.a)); p(k + "hex", Color.hex(c.to_rgba32()))
		p(k + "hex64", Color.hex64(c.to_rgba64())); p(k + "html_rt", Color.html(c.to_html()))
		for j in C.size():
			var d: Color = C[j]
			var kk := k + "%d." % j
			p(kk + "lerp", c.lerp(d, 0.3)); p(kk + "blend", c.blend(d)); p(kk + "add", c + d); p(kk + "sub", c - d); p(kk + "mul", c * d); p(kk + "div", c / d)
			p(kk + "iea", c.is_equal_approx(d)); p(kk + "eq", c == d)
	for s in ["#fff", "ffff", "#12345678", "abcdef", "#ABC", "zz", "#12345", "red", "Light Sky Blue", "rebecca-purple", "web_gray", "nope", ""]:
		p("cs.%s.valid" % s, Color.html_is_valid(s)); p("cs.%s.from" % s, Color.from_string(s, Color(0.1, 0.2, 0.3)))
	for s in ["#fff", "ffff", "#12345678", "abcdef", "#ABC"]:
		p("cs.%s.html" % s, Color.html(s)); p("cs.%s.ctor" % s, Color(s)); p("cs.%s.ctora" % s, Color(s, 0.5))
	for h in [0.0, 0.1, 0.5, 0.99, 1.0, 1.5, -0.25]:
		p("chsv.%s" % h, Color.from_hsv(h, 0.7, 0.9)); p("cokhsl.%s" % h, Color.from_ok_hsl(h, 0.7, 0.6)); p("cokhsl0.%s" % h, Color.from_ok_hsl(h, 0.3, 0.0))
	p("crgba8", Color.from_rgba8(255, 128, 0)); p("crgba8b", Color.from_rgba8(12, 34, 56, 78)); p("crgbe", Color.from_rgbe9995(0x12345678))
	p("cnamed", [Color.ALICE_BLUE, Color.WEB_PURPLE, Color.MEDIUM_SPRING_GREEN, Color.LIGHT_GOLDENROD, Color.LIME, Color.FUCHSIA])

func variant_cases() -> void:
	var b: Variant = Basis.from_euler(Vector3(0.1, 0.2, 0.3))
	var q: Variant = Quaternion.from_euler(Vector3(0.3, -0.2, 0.1))
	var t: Variant = Transform3D(Basis.from_euler(Vector3(0.5, 0.1, -0.2)), Vector3(1, 2, 3))
	var v: Variant = Vector3(1, -2, 0.5)
	var a: Variant = AABB(Vector3(-1, 0, 1), Vector3(2, 3, 4))
	var pl: Variant = Plane(Vector3(0, 1, 0), 2)
	var x2: Variant = Transform2D(0.5, Vector2(1, 2))
	var v2: Variant = Vector2(3, -1)
	var r2: Variant = Rect2(0, 1, 2, 3)
	var pr: Variant = Projection.create_perspective(60, 1.5, 0.1, 100)
	var v4: Variant = Vector4(1, 2, 3, 1)
	var c: Variant = Color(0.2, 0.4, 0.6, 0.8)
	var v3i: Variant = Vector3i(3, -4, 5)
	var v4i: Variant = Vector4i(3, -4, 5, 6)
	p("var.bv", b * v); p("var.vb", v * b); p("var.bb", b * b); p("var.b2", b * 2); p("var.bd2", b / 2.0)
	p("var.qv", q * v); p("var.vq", v * q); p("var.qq", q * q); p("var.q2", 2 * q); p("var.qn", -q); p("var.qa", q + q)
	p("var.tv", t * v); p("var.vt", v * t); p("var.ta", t * a); p("var.at", a * t); p("var.tp", t * pl); p("var.pt", pl * t); p("var.tt", t * t)
	p("var.xv", x2 * v2); p("var.vx", v2 * x2); p("var.xr", x2 * r2); p("var.rx", r2 * x2); p("var.xx", x2 * x2); p("var.x2", x2 * 2.0)
	p("var.prv", pr * v4); p("var.vpr", v4 * pr); p("var.prpr", pr * pr)
	p("var.c2", c * 2); p("var.2c", 2.0 * c); p("var.cn", -c); p("var.cc", c * c); p("var.cdc", c / c); p("var.cp", c + c)
	p("var.pn", -pl); p("var.v3i25", v3i * 2.5); p("var.v3id2", v3i / 2); p("var.v3im3", v3i % 3); p("var.v3iv", v3i + v3i); p("var.v3in", -v3i)
	p("var.v4m", v4 * 2); p("var.2v4", 2.5 * v4); p("var.v4d", v4 / v4); p("var.v4i3", 3 * v4i); p("var.v4if", v4i * 0.5)
	for x in [b, q, t, a, pl, x2, r2, pr, v4, c, v3i, v4i, Basis(), Quaternion(), Transform3D(), AABB(), Plane(), Transform2D(), Rect2(), Projection(), Vector4(), Color(), Vector3i(), Vector4i()]:
		p("var.info", [typeof(x), hash(x), true if x else false, str(x)])
	p("var.eq", [b == Basis.from_euler(Vector3(0.1, 0.2, 0.3)), q == q, t == Transform3D(), c == Color(0.2, 0.4, 0.6, 0.8), v3i == Vector3i(3, -4, 5)])

func edge_cases() -> void:
	var E2 := [Vector2(INF, 1), Vector2(NAN, 2), Vector2(-0.0, 0.0), Vector2(-INF, -INF)]
	for i in E2.size():
		var a: Vector2 = E2[i]
		var k := "e2.%d." % i
		p(k + "str", a); p(k + "norm", a.normalized()); p(k + "fin", a.is_finite()); p(k + "sign", a.sign()); p(k + "clampf", a.clampf(-1, 1))
		p(k + "minf", a.minf(0.5)); p(k + "maxf", a.maxf(0.5)); p(k + "snap0", a.snappedf(0)); p(k + "posmod", a.posmod(-0.7)); p(k + "hash", hash(a)); p(k + "lim", a.limit_length(2))
	var E3 := [Vector3(INF, 1, 0), Vector3(NAN, 2, 3), Vector3(-0.0, 0.0, -0.0), Vector3(1, -INF, 0)]
	for i in E3.size():
		var a: Vector3 = E3[i]
		var k := "e3.%d." % i
		p(k + "str", a); p(k + "norm", a.normalized()); p(k + "fin", a.is_finite()); p(k + "sign", a.sign()); p(k + "clamp", a.clamp(Vector3(-1, -1, -1), Vector3(1, 1, 1)))
		p(k + "min", a.min(Vector3(0.5, 0.5, 0.5))); p(k + "max", a.max(Vector3(0.5, 0.5, 0.5))); p(k + "snap0", a.snapped(Vector3(0, 0.5, 0))); p(k + "hash", hash(a))
		p(k + "dir", Vector3(1, 1, 1).direction_to(a)); p(k + "octd", Vector3.octahedron_decode(Vector2(a.x, a.y))); p(k + "eul", Basis.from_euler(a).get_euler())
	p("e.q", [Quaternion(NAN, 0, 0, 1).normalized(), Quaternion(0, 0, 0, 1).slerp(Quaternion(0, 0, 0, -1), 0.5), Quaternion(0, 0, 0, 1).angle_to(Quaternion(0, 1, 0, 0))])
	p("e.c", [Color(NAN, 0.5, 0.5).get_luminance(), Color(-0.0, 0, 0).h, Color(1, 1, 1).s, hash(Color(-0.0, 0, 0, 1)), hash(Color(0, 0, 0, 1))])
