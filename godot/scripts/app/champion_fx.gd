extends Control
# 0.31.187 (Kevin: "Use art and effects that match each characters lore"): a champion's effects over his painting in his
# window (champion_window.gd) -- the layers Champions.CHAMPIONS[hid].fx names: the Barbarian's bonfire embers and the
# snow, the Druid's leaves and fireflies, the Stormcaller's rain and lightning, the Archmage's stars and a meteor now and
# then... Drawn here as sprites (assets/vfx/weapon/, the weapons' own effect sprites) moved by hand: a few dozen, cheap,
# the same on every renderer. Two of these sit behind the champion (halo, orbit, twinkle, rise, flash, meteor) and two in
# front (fall, rain, drift), each in one blend: glows added (light), smoke, leaves, feathers, stones and snow laid over.
const SPRITE := "res://assets/vfx/weapon/%s.png"
const FRONT := ["fall", "rain", "drift"]
const LAID := ["smoke", "leaf", "feather", "shard", "snowflake"]      # (the rest add light)

var front := false
var additive := true
var center := Vector2(0.5, 0.42)            # where the champion stands, as a fraction of the rect (orbit and halo round it)
var layers: Array = []                      # [{tex, color, motion, n, size}]
var parts: Array = []                       # every sprite: {l (its layer), p, v, life, age, rot, spin, s, ph}
var events: Array = []                      # flash / meteor: {l, next, age, at, dir}
var _flash := 0.0
var _t := 0.0
var rng := RandomNumberGenerator.new()
static var _laid_shader: Shader
const LAID_SHADER := """shader_type canvas_item;
varying vec4 tint;
void vertex() { tint = COLOR; }
void fragment() {
	float l = texture(TEXTURE, UV).r;
	COLOR = vec4(tint.rgb * (0.55 + 0.6 * l), tint.a * smoothstep(0.03, 0.45, l));
}
"""

static func wants(layer: Array, in_front: bool, add: bool) -> bool:
	return (str(layer[2]) in FRONT) == in_front and (not (str(layer[0]) in LAID)) == add

func setup(fx: Array, in_front: bool, add: bool, at := Vector2(0.5, 0.42)) -> void:
	front = in_front
	additive = add
	center = at
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rng.seed = hash(str(fx)) + (1 if in_front else 0) + (2 if add else 0)
	if add:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m
	else:
		# (the sprites are brightness only, white on black -- made to be added: laid over, the brightness is the shape)
		if _laid_shader == null:
			_laid_shader = Shader.new()
			_laid_shader.code = LAID_SHADER
		var sm := ShaderMaterial.new()
		sm.shader = _laid_shader
		material = sm
	for l in fx:
		if not wants(l, in_front, add):
			continue
		var path := SPRITE % str(l[0])
		var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
		if t == null:
			continue
		layers.append({"tex": t, "color": Color(str(l[1])), "motion": str(l[2]), "n": int(l[3]), "size": float(l[4])})
	resized.connect(_spawn_all)
	_spawn_all()

func count() -> int:
	return parts.size() + events.size()

func _spawn_all() -> void:
	parts.clear()
	events.clear()
	if size.x < 8 or size.y < 8:
		return
	for li in layers.size():
		var L: Dictionary = layers[li]
		match str(L.motion):
			"flash", "meteor":
				events.append({"l": li, "next": rng.randf_range(0.6, 2.5), "age": -1.0, "at": Vector2.ZERO, "dir": 1.0})
			"halo":
				parts.append({"l": li, "p": size * center, "v": Vector2.ZERO, "life": 1e9, "age": 0.0, "rot": 0.0,
					"spin": 0.08, "s": 1.0, "ph": 0.0})
			_:
				for i in int(L.n):
					var q := _new_part(li, true)
					parts.append(q)

func _new_part(li: int, warm: bool) -> Dictionary:
	# a new sprite of layer li (warm: anywhere along its way, so the window opens already full)
	var L: Dictionary = layers[li]
	var w := size.x
	var h := size.y
	var s := rng.randf_range(0.7, 1.3)
	var q := {"l": li, "rot": rng.randf_range(0, TAU), "spin": rng.randf_range(-1.2, 1.2), "s": s, "ph": rng.randf_range(0, TAU),
		"age": 0.0}
	match str(L.motion):
		"rise":
			var sp := rng.randf_range(18.0, 46.0)
			q.p = Vector2(rng.randf_range(0.05, 0.95) * w, h * rng.randf_range(0.78, 1.0))
			q.v = Vector2(rng.randf_range(-6, 6), -sp)
			q.life = h * rng.randf_range(0.45, 0.8) / sp
			q.spin = rng.randf_range(-0.6, 0.6)
		"fall":
			var fs := rng.randf_range(24.0, 52.0)
			q.p = Vector2(rng.randf_range(-0.05, 1.05) * w, -float(L.size) * 2.0)
			q.v = Vector2(rng.randf_range(4, 18), fs)
			q.life = (h + float(L.size) * 4.0) / fs
		"drift":
			var smoke := float(L.size) > 60.0
			var ds := rng.randf_range(10.0, 26.0) if smoke else rng.randf_range(45.0, 95.0)
			q.p = Vector2(-float(L.size) * s, h * rng.randf_range(0.18, 0.85))
			q.v = Vector2(ds, rng.randf_range(-8, 4))
			q.life = (w + float(L.size) * 2.6) / ds
			q.spin = rng.randf_range(-0.15, 0.15) if smoke else rng.randf_range(-2.0, 2.0)
		"twinkle":
			q.p = Vector2(rng.randf_range(0.04, 0.96) * w, rng.randf_range(0.06, 0.78) * h)
			q.v = Vector2(0, rng.randf_range(-4, 0))
			q.life = rng.randf_range(1.6, 3.6)
			q.spin = rng.randf_range(-0.4, 0.4)
		"rain":
			var rs := rng.randf_range(520.0, 760.0)
			q.p = Vector2(rng.randf_range(-0.1, 1.2) * w, -30.0)
			q.v = Vector2(-rs * 0.28, rs)
			q.life = (h + 60.0) / rs
			q.rot = atan2(q.v.y, q.v.x) - PI * 0.5
			q.spin = 0.0
		"orbit":
			q.p = size * center
			q.v = Vector2.ZERO
			q.life = 1e9
			q.ph = TAU * float(parts.filter(func(o): return int(o.l) == li).size()) / maxf(1.0, float(L.n))
			q.spin = rng.randf_range(-0.5, 0.5)
		_:
			q.p = Vector2(rng.randf() * w, rng.randf() * h)
			q.v = Vector2.ZERO
			q.life = 2.0
	if warm and float(q.life) < 1e8:
		var a := rng.randf_range(0.0, float(q.life))
		q.age = a
		q.p = (q.p as Vector2) + (q.v as Vector2) * a
	return q

func _process(delta: float) -> void:
	if not is_visible_in_tree() or layers.is_empty():
		return
	delta = minf(delta, 0.1)
	_t += delta
	for i in parts.size():
		var q: Dictionary = parts[i]
		q.age = float(q.age) + delta
		q.p = (q.p as Vector2) + (q.v as Vector2) * delta
		q.rot = float(q.rot) + float(q.spin) * delta
		if float(q.age) >= float(q.life):
			parts[i] = _new_part(int(q.l), false)
	_flash = maxf(0.0, _flash - delta * 2.2)
	for e in events:
		var L: Dictionary = layers[int(e.l)]
		if float(e.age) < 0.0:
			e.next = float(e.next) - delta
			if float(e.next) <= 0.0:
				e.age = 0.0
				e.dir = -1.0 if rng.randf() < 0.5 else 1.0
				if str(L.motion) == "flash":
					e.at = Vector2(rng.randf_range(0.15, 0.85) * size.x, rng.randf_range(0.02, 0.2) * size.y)
					_flash = 1.0
				else:
					e.at = Vector2((0.1 if e.dir > 0 else 0.9) * size.x, rng.randf_range(0.02, 0.14) * size.y)
		else:
			e.age = float(e.age) + delta
			var dur := 0.45 if str(L.motion) == "flash" else 1.1
			if float(e.age) > dur:
				e.age = -1.0
				e.next = rng.randf_range(2.5, 6.5) if str(L.motion) == "flash" else rng.randf_range(4.0, 8.0)
	queue_redraw()

func _sprite(tex: Texture2D, at: Vector2, px: float, rot: float, c: Color, sx := 1.0, sy := 1.0) -> void:
	draw_set_transform(at, rot, Vector2(sx, sy))
	draw_texture_rect(tex, Rect2(-px * 0.5, -px * 0.5, px, px), false, c)

func _draw() -> void:
	for q in parts:
		var L: Dictionary = layers[int(q.l)]
		var tex: Texture2D = L.tex
		var c: Color = L.color
		var px := float(L.size) * float(q.s)
		var life := float(q.life)
		var u := clampf(float(q.age) / life, 0.0, 1.0) if life < 1e8 else 0.0
		var a := 1.0
		match str(L.motion):
			"rise":
				a = minf(u / 0.15, 1.0) * minf((1.0 - u) / 0.35, 1.0) * 0.85
				var sway := sin(_t * 1.6 + float(q.ph)) * 10.0
				_sprite(tex, (q.p as Vector2) + Vector2(sway, 0), px, float(q.rot), Color(c, c.a * a))
			"fall":
				a = minf(u / 0.08, 1.0) * minf((1.0 - u) / 0.12, 1.0) * 0.95
				var sw := sin(_t * 1.3 + float(q.ph)) * 26.0
				_sprite(tex, (q.p as Vector2) + Vector2(sw, 0), px, float(q.rot), Color(c, c.a * a), cos(_t * 2.6 + float(q.ph)), 1.0)
			"drift":
				a = minf(u / 0.12, 1.0) * minf((1.0 - u) / 0.12, 1.0) * (0.32 if float(L.size) > 60.0 else 0.85)
				var wv := sin(_t * 0.9 + float(q.ph)) * 6.0
				_sprite(tex, (q.p as Vector2) + Vector2(0, wv), px, float(q.rot), Color(c, c.a * a))
			"twinkle":
				a = sin(PI * u)
				_sprite(tex, q.p, px * (0.7 + 0.3 * a), float(q.rot), Color(c, c.a * a * 0.9))
			"rain":
				_sprite(tex, q.p, px, float(q.rot), Color(c, c.a * 0.32), 0.22, 3.4)
			"orbit":
				var ang := float(q.ph) + _t * 0.32
				var o := size * center + Vector2(cos(ang) * size.x * 0.34, sin(ang) * size.y * 0.035)
				var near := 0.5 + 0.5 * sin(ang)           # (round the front: brighter and bigger)
				a = (0.28 + 0.4 * near) * (0.8 + 0.2 * sin(_t * 2.0 + float(q.ph)))
				_sprite(tex, o, px * (0.8 + 0.3 * near), float(q.rot), Color(c, c.a * a))
			"halo":
				a = 0.32 + 0.1 * sin(_t * 1.1)
				_sprite(tex, size * center, px * (1.0 + 0.04 * sin(_t * 0.7)), _t * float(q.spin), Color(c, c.a * a))
	for e in events:
		if float(e.age) < 0.0:
			continue
		var L2: Dictionary = layers[int(e.l)]
		var c2: Color = L2.color
		var px2 := float(L2.size)
		if str(L2.motion) == "flash":
			var k := float(e.age) / 0.45
			var fl := 1.0 if k < 0.2 else (0.35 if k < 0.35 else (0.9 if k < 0.55 else 1.0 - k))
			_sprite(L2.tex, (e.at as Vector2) + Vector2(0, px2 * 0.5), px2, 0.0, Color(c2, clampf(fl, 0.0, 1.0)), float(e.dir), 1.0)
		else:
			var m := float(e.age) / 1.1
			var head := (e.at as Vector2) + Vector2(float(e.dir) * size.x * 0.75 * m, size.y * 0.3 * m)
			var step := Vector2(-float(e.dir) * 9.0, -3.6)
			for j in 9:
				var aa := (1.0 - float(j) / 9.0) * sin(PI * m)
				_sprite(L2.tex, head + step * float(j), px2 * (1.0 - float(j) * 0.07), 0.0, Color(c2, c2.a * aa))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.75, 0.85, 1.0, 0.16 * _flash))
