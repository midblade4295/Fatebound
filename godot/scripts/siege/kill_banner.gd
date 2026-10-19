extends Control
# 0.31.180 (Kevin: "Make banner in middle of screen when a player kills another player. It'll show "name" has slain
# "name"" -- with League's multi-kills, ACE, First Blood and Shutdown -- "I want the banner art created by eleven so
# they look more detailed. I also want special effects on the kill streak and first blood ones"): the 5v5's kill
# banners, one at a time a little above the middle of the screen, from the sim's "kb" and "ace" events.
#  - every hero kill: the name plaque (assets/ui/banners/plaque_*, ElevenLabs), the killer's portrait and the victim's
#    (greyed, a skull on it) in its sockets, "<killer>  HAS SLAIN  <victim>" between them -- names in their sides'
#    colours (yours gold); blue when your side made the kill, red when the enemy did;
#  - over it the painted title for FIRST BLOOD, DOUBLE / TRIPLE / QUADRA KILL, PENTAKILL and SHUTDOWN (the gold paid
#    under the plaque); ACE on its own with the five fallen;
#  - each slams in (big, then settling), holds, fades. Effects: a light sweeps across the title; FIRST BLOOD bursts
#    blood from its medallion, drips from its edge and flashes the screen's edges red; DOUBLE silver sparks; TRIPLE
#    gold sparks and embers; QUADRA light rays turning behind its crest and a burst of gold; PENTAKILL bigger rays,
#    gold confetti falling, sparks, and the screen's edges glowing gold all the while; SHUTDOWN embers and gold coins
#    bursting from the broken crown; ACE blue rays and stars.
#  - a newer banner cuts short the one showing (after a moment), so a QUADRA doesn't wait behind a TRIPLE.
const DIR := "res://assets/ui/banners/"
const MULTI_ART := ["", "", "double", "triple", "quadra", "penta"]
# the art's width on screen (HUD units, the HUD ~420 wide) and how far its foot sits over the plaque
const ART_W := {"first_blood": 330.0, "double": 320.0, "triple": 340.0, "shutdown": 330.0, "quadra": 236.0, "penta": 290.0,
	"ace": 220.0}
const ART_TUCK := {"first_blood": 10.0, "double": 6.0, "triple": 8.0, "shutdown": 10.0, "quadra": 14.0, "penta": 18.0, "ace": 0.0}
const PLAQUE_W := 340.0
const PLAQUE_SOCKETS := [Vector3(0.1114, 0.5, 0.31), Vector3(0.8873, 0.5, 0.31)]   # (x, y of the plaque; r of its height)
const LIFE := {"kill": 2.4, "first_blood": 3.2, "double": 2.8, "triple": 3.0, "quadra": 3.5, "penta": 4.6, "shutdown": 3.2,
	"ace": 3.4}
const OUT := 0.35                       # the fade at the end
const CUT_AFTER := 0.8                  # a newer banner may cut the one showing short after this long
const SIDE_COL := [Color("#7fe0ff"), Color("#ff8f6a")]
const YOU_COL := Color("#ffd65a")
const SHINE_CODE := """
shader_type canvas_item;
uniform float sweep = -1.0;
uniform float width = 0.11;
uniform float strength = 0.75;
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float d = (UV.x + UV.y * 0.4) / 1.4 - sweep;
	float b = smoothstep(width, 0.0, abs(d)) * strength;
	c.rgb += vec3(1.0, 0.95, 0.82) * b * c.a;
	COLOR = c;
}
"""

var hud                                 # siege_hud.gd: names, sides, portraits
var queue: Array = []
var cur: Dictionary = {}
var age := 0.0
var parts: Array = []
var shown: Array = []                   # (tests: every banner started, in order: its "style")
var _tex := {}
var _art: TextureRect
var _front: Control
var _shine: ShaderMaterial
var _lg: Font
var _rng := RandomNumberGenerator.new()
var _drip_t := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lg = load("res://assets/fonts/LuckiestGuy-Regular.ttf")
	_rng.seed = 180
	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.visible = false
	var sh := Shader.new()
	sh.code = SHINE_CODE
	_shine = ShaderMaterial.new()
	_shine.shader = sh
	_art.material = _shine
	add_child(_art)
	_front = Control.new()
	_front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_front.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_front.draw.connect(_draw_front)
	add_child(_front)

func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		var p := DIR + name + ".png"
		if name.begins_with("res://"):
			p = name
		_tex[name] = load(p) if ResourceLoader.exists(p) else null
	return _tex[name]

func portrait(u: Dictionary) -> Texture2D:
	return tex("res://assets/ui/skins/default_%s.png" % str(u.get("hid", u.get("cls", "knight"))))

func busy() -> bool:
	return not cur.is_empty()

# ---------- what to show ----------
func push(e: Dictionary) -> void:
	var item := {}
	match str(e.get("k", "")):
		"kb":
			var kind := str(e.get("kind", "kill"))
			var style := kind
			if kind == "multi":
				style = MULTI_ART[clampi(int(e.get("n", 2)), 2, 5)]
			item = {"style":style, "by":str(e.get("by", "")), "id":str(e.get("id", "")), "bounty":int(e.get("bounty", 0)),
				"shut":bool(e.get("shut", false)) or kind == "shutdown"}
		"ace":
			item = {"style":"ace", "by":str(e.get("by", "")), "ids":e.get("ids", []), "team":int(e.get("team", -1))}
		_:
			return
	queue.append(item)
	while queue.size() > 4:
		# (a long run of kills: the plain ones go first)
		var drop := -1
		for i in queue.size():
			if str(queue[i].style) == "kill":
				drop = i
				break
		queue.remove_at(drop if drop >= 0 else 0)

func _start(item: Dictionary) -> void:
	cur = item.duplicate()
	cur["life"] = float(LIFE.get(str(item.style), 2.4))
	age = 0.0
	_drip_t = 0.0
	shown.append(str(item.style))
	var st := str(item.style)
	var t: Texture2D = tex(st) if st != "kill" else null
	_art.texture = t
	_art.visible = t != null
	_burst(st)

# ---------- the frame ----------
func _process(delta: float) -> void:
	if cur.is_empty() and queue.is_empty() and parts.is_empty():
		if _art.visible:
			_art.visible = false
		return
	age += delta
	if not cur.is_empty() and not queue.is_empty() and age > CUT_AFTER:
		cur.life = minf(float(cur.life), age + OUT)     # (one waiting: this one goes after its moment)
	if not cur.is_empty() and age >= float(cur.life):
		cur = {}
		_art.visible = false
	if cur.is_empty() and not queue.is_empty():
		_start(queue.pop_front())
	_step_parts(delta)
	_place_art()
	queue_redraw()
	_front.queue_redraw()

func center() -> Vector2:
	# the plaque's middle: a little above the middle of the screen, under the top bar and the kill feed
	return Vector2(size.x * 0.5, clampf(size.y * 0.36, 290.0, 420.0))

func scale_now() -> float:
	if cur.is_empty():
		return 1.0
	var big := 1.55 if str(cur.style) in ["quadra", "penta", "ace", "first_blood"] else 1.35
	if age < 0.16:
		return lerpf(big, 0.93, ease(age / 0.16, 0.5))
	if age < 0.3:
		return lerpf(0.93, 1.0, (age - 0.16) / 0.14)
	return 1.0

func alpha_now() -> float:
	if cur.is_empty():
		return 0.0
	return clampf(age / 0.08, 0.0, 1.0) * clampf((float(cur.life) - age) / OUT, 0.0, 1.0)

func art_rect() -> Rect2:
	# the title art's rect at rest (before the slam's scale), its foot tucked over the plaque
	var st := str(cur.get("style", ""))
	var t: Texture2D = _art.texture
	if t == null:
		return Rect2(center(), Vector2.ZERO)
	var w: float = ART_W.get(st, 320.0)
	var h := w * float(t.get_height()) / float(t.get_width())
	var c := center()
	var foot := c.y - plaque_size().y * 0.5 + float(ART_TUCK.get(st, 8.0))
	if st == "ace":
		foot = c.y + 30.0
	return Rect2(Vector2(c.x - w * 0.5, foot - h), Vector2(w, h))

func plaque_size() -> Vector2:
	var t := tex("plaque_blue")
	return Vector2(PLAQUE_W, PLAQUE_W * (float(t.get_height()) / float(t.get_width()) if t != null else 0.18))

func _place_art() -> void:
	if not _art.visible:
		return
	var r := art_rect()
	var s := scale_now()
	var c := center()
	_art.size = r.size
	_art.pivot_offset = c - r.position          # (scaled round the banner's middle, with the plaque)
	_art.position = r.position + Vector2(0, -10.0 * (1.0 - clampf((float(cur.life) - age) / OUT, 0.0, 1.0)))
	_art.scale = Vector2(s, s)
	_art.modulate = Color(1, 1, 1, alpha_now())
	# the light across the title: once as it lands; again and again on the big ones
	var period := 1.5 if str(cur.style) in ["triple", "quadra", "penta", "ace", "first_blood"] else 99.0
	var tt := fmod(maxf(0.0, age - 0.22), period)
	_shine.set_shader_parameter("sweep", -0.2 + tt / 0.7 * 1.4 if tt < 0.7 else -1.0)

# ---------- behind the art: rays, the screen's edges ----------
func _draw() -> void:
	if cur.is_empty():
		return
	var st := str(cur.style)
	var a := alpha_now()
	var ar := art_rect()
	var ac := ar.get_center()
	match st:
		"quadra":
			_rays(ac, 210.0, 14, Color(1.0, 0.85, 0.4, 0.33 * a), 0.35)
		"penta":
			_rays(ac, 300.0, 18, Color(1.0, 0.86, 0.42, 0.42 * a), 0.25)
			_edges(Color(1.0, 0.78, 0.25, (0.38 + 0.14 * sin(age * 6.0)) * a), 90.0)
		"ace":
			_rays(ac, 190.0, 12, Color(0.55, 0.85, 1.0, 0.3 * a), 0.4)
		"first_blood":
			var k := clampf(1.0 - age / 0.9, 0.0, 1.0)
			if k > 0.0:
				_edges(Color(0.85, 0.04, 0.06, 0.55 * k), 70.0)
			if age < 0.5:
				draw_arc(ac, 40.0 + age * 420.0, 0.0, TAU, 48, Color(1.0, 0.2, 0.2, 0.6 * (1.0 - age / 0.5)), 5.0, true)
		"shutdown":
			if age < 0.45:
				draw_arc(ac, 30.0 + age * 380.0, 0.0, TAU, 48, Color(1.0, 0.55, 0.15, 0.55 * (1.0 - age / 0.45)), 5.0, true)
	if st in ["quadra", "penta", "ace"]:
		draw_circle(ac, ar.size.x * 0.42, Color(1.0, 0.9, 0.5, 0.12 * a) if st != "ace" else Color(0.6, 0.85, 1.0, 0.12 * a))

func _rays(c: Vector2, r: float, n: int, col: Color, speed: float) -> void:
	var rot := age * speed
	var clear := Color(col.r, col.g, col.b, 0.0)
	for i in n:
		var a0 := rot + TAU * float(i) / float(n)
		var a1 := a0 + PI / float(n) * 0.75
		draw_polygon(PackedVector2Array([c, c + Vector2.from_angle(a0) * r, c + Vector2.from_angle(a1) * r]),
			PackedColorArray([col, clear, clear]))

func _edges(col: Color, w: float) -> void:
	var clear := Color(col.r, col.g, col.b, 0.0)
	var W := size.x
	var H := size.y
	for q in [[Vector2(0, 0), Vector2(W, 0), Vector2(W, w), Vector2(0, w)], [Vector2(0, H), Vector2(W, H), Vector2(W, H - w), Vector2(0, H - w)],
			[Vector2(0, 0), Vector2(0, H), Vector2(w, H), Vector2(w, 0)], [Vector2(W, 0), Vector2(W, H), Vector2(W - w, H), Vector2(W - w, 0)]]:
		draw_polygon(PackedVector2Array(q), PackedColorArray([col, col, clear, clear]))

# ---------- in front: the plaque, the names, the gold, the particles ----------
func _draw_front() -> void:
	if not cur.is_empty():
		var a := alpha_now()
		var s := scale_now()
		var c := center()
		var lift := -10.0 * (1.0 - clampf((float(cur.life) - age) / OUT, 0.0, 1.0))
		_front.draw_set_transform(c + Vector2(0, lift), 0.0, Vector2(s, s))
		if str(cur.style) == "ace":
			_draw_ace(a)
		else:
			_draw_plaque(a)
		_front.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for p in parts:
		_draw_part(p)

func _unit(id: String) -> Dictionary:
	return hud.sim.by_id.get(id, {}) if hud != null and hud.sim != null else {}

func _name_col(u: Dictionary) -> Color:
	if u.is_empty():
		return Color.WHITE
	if str(u.id) == str(hud.player_id):
		return YOU_COL
	return SIDE_COL[hud.vt(int(u.team))] if int(u.team) <= 1 else Color.WHITE

func _draw_plaque(a: float) -> void:
	var k := _unit(str(cur.get("by", "")))
	var v := _unit(str(cur.get("id", "")))
	var ours: bool = not k.is_empty() and hud.vt(int(k.team)) == 0
	var pt := tex("plaque_blue" if ours else "plaque_red")
	var ps := plaque_size()
	var r := Rect2(-ps * 0.5, ps)
	var w := Color(1, 1, 1, a)
	if pt != null:
		_front.draw_texture_rect(pt, r, false, w)
	else:
		_front.draw_rect(r, Color(0.05, 0.1, 0.16, 0.9 * a))
	# the two portraits in their sockets
	for i in 2:
		var sk: Vector3 = PLAQUE_SOCKETS[i]
		var pc := r.position + Vector2(sk.x * ps.x, sk.y * ps.y)
		var pr := sk.z * ps.y * 1.04
		var who := k if i == 0 else v
		_disc(portrait(who), pc, pr, Color(1, 1, 1, a) if i == 0 else Color(0.5, 0.5, 0.56, a))
		if i == 1:
			var sk_t := tex("res://assets/ui/v2/icons/skull.png")
			if sk_t != null:
				_front.draw_texture_rect(sk_t, Rect2(pc + Vector2(pr * 0.2, pr * 0.05), Vector2(pr * 1.1, pr * 1.1)), false, w)
	# "<killer>  HAS SLAIN  <victim>", fitted between the sockets
	var room := ps.x * (PLAQUE_SOCKETS[1].x - PLAQUE_SOCKETS[0].x) - ps.y * 0.85
	var names := line_names()
	var kn: String = names[0]
	var vn: String = names[1]
	var bold: Font = hud._bold
	var title: Font = hud._title
	var fs := 15
	var verb := "HAS SLAIN"
	var vs := 9
	var tw := 0.0
	while fs > 9:
		tw = bold.get_string_size(kn, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + bold.get_string_size(vn, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x \
			+ title.get_string_size(verb, HORIZONTAL_ALIGNMENT_LEFT, -1, vs).x + 14.0
		if tw <= room:
			break
		fs -= 1
	var x := -tw * 0.5
	var base := float(fs) * 0.36
	x = _word(kn, bold, fs, Vector2(x, base), _name_col(k), a) + 7.0
	x = _word(verb, title, vs, Vector2(x, base - 1.0), Color("#f2d18d"), a) + 7.0
	_word(vn, bold, fs, Vector2(x, base), _name_col(v), a)
	# a SHUTDOWN's gold: the kill and the bounty
	if bool(cur.get("shut", false)) and int(cur.get("bounty", 0)) > 0:
		var total := 300 + int(cur.bounty)
		var txt := "+%d" % total
		var cw := _lg.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x + 40.0
		var cr := Rect2(Vector2(-cw * 0.5, ps.y * 0.5 + 6.0), Vector2(cw, 32.0))
		_front.draw_rect(cr, Color(0.12, 0.07, 0.01, 0.85 * a))
		_front.draw_rect(cr, Color(0.88, 0.69, 0.28, a), false, 2.0)
		var coin := tex("res://assets/ui/currency/coin.png")
		if coin != null:
			_front.draw_texture_rect(coin, Rect2(cr.position + Vector2(5, 3), Vector2(26, 26)), false, w)
		_word(txt, _lg, 24, cr.position + Vector2(34, 26), Color("#ffd65a"), a)
		var sub := "%d BOUNTY" % int(cur.bounty)
		var sw := bold.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		_word(sub, bold, 10, Vector2(-sw * 0.5, cr.end.y + 13.0), Color("#e8dcc0"), a)

func line_names() -> Array:
	# the plaque's two names: [killer, victim] (as the HUD names them: yours, a player's, "Bot <name>")
	var k := _unit(str(cur.get("by", "")))
	var v := _unit(str(cur.get("id", "")))
	return [hud.display_name(k) if not k.is_empty() else "?", hud.display_name(v) if not v.is_empty() else "?"]

func _draw_ace(a: float) -> void:
	# the five fallen in a row under the crest, and who sealed it
	var ids: Array = cur.get("ids", [])
	var n := ids.size()
	var d := 46.0
	var x0 := -(float(n) * (d + 6.0) - 6.0) * 0.5 + d * 0.5
	var y := 58.0
	var w := Color(1, 1, 1, a)
	var sk_t := tex("res://assets/ui/v2/icons/skull.png")
	for i in n:
		var u := _unit(str(ids[i]))
		var pc := Vector2(x0 + float(i) * (d + 6.0), y)
		_front.draw_circle(pc, d * 0.5 + 3.0, Color(0.7, 0.53, 0.2, a))
		_disc(portrait(u), pc, d * 0.5, Color(0.5, 0.5, 0.56, a))
		if sk_t != null:
			_front.draw_texture_rect(sk_t, Rect2(pc + Vector2(4, 2), Vector2(22, 22)), false, w)
	var k := _unit(str(cur.get("by", "")))
	var ours: bool = int(cur.get("team", -1)) >= 0 and hud.vt(int(cur.team)) == 0
	var line := ("%s SEALED IT" % hud.display_name(k).to_upper()) if not k.is_empty() else "THE WHOLE SIDE IS DOWN"
	if not ours:
		line = "YOUR WHOLE SIDE IS DOWN"
	var lw: float = hud._title.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	_word(line, hud._title, 12, Vector2(-lw * 0.5, y + d * 0.5 + 22.0), Color("#f2d18d") if ours else Color("#ff8f6a"), a)

func _word(t: String, f: Font, fs: int, p: Vector2, col: Color, a: float) -> float:
	col.a *= a
	_front.draw_string_outline(f, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0.03, 0.02, 0.05, 0.85 * a))
	_front.draw_string(f, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	return p.x + f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x

func _disc(t: Texture2D, c: Vector2, r: float, mod: Color) -> void:
	# a portrait clipped to a circle
	if t == null:
		_front.draw_circle(c, r, Color(0.1, 0.12, 0.16, mod.a))
		return
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in 32:
		var v := Vector2.from_angle(TAU * float(i) / 32.0)
		pts.append(c + v * r)
		uvs.append(Vector2(0.5, 0.46) + v * 0.46)
	_front.draw_polygon(pts, PackedColorArray([mod]), uvs, t)

# ---------- particles ----------
func _burst(st: String) -> void:
	var ar := art_rect()
	var ac := ar.get_center()
	var top := Vector2(ac.x, ar.position.y + ar.size.y * 0.22)
	match st:
		"first_blood":
			for i in 46:
				var dir := Vector2.from_angle(-PI * 0.5 + _rng.randf_range(-1.35, 1.35))
				_add({"kind":"blood", "p":top, "v":dir * _rng.randf_range(160.0, 380.0), "life":_rng.randf_range(0.8, 1.4),
					"size":_rng.randf_range(3.5, 7.0), "col":Color(0.86, 0.05, 0.08), "g":620.0})
		"double":
			_sparks(ac, 26, Color(0.92, 0.96, 1.0), 260.0)
		"triple":
			_sparks(ac, 34, Color(1.0, 0.86, 0.38), 300.0)
			for i in 14:
				_ember(ar, Color(1.0, 0.7, 0.25))
		"quadra":
			_sparks(ac, 44, Color(1.0, 0.86, 0.38), 340.0)
			for i in 10:
				_coin(ac, 260.0)
		"penta":
			_sparks(ac, 60, Color(1.0, 0.9, 0.45), 380.0)
			for i in 12:
				_coin(ac, 300.0)
			for i in 40:
				_confetti(true)
		"shutdown":
			for i in 14:
				_coin(top, 280.0)
			for i in 20:
				_ember(ar, Color(1.0, 0.45, 0.12))
		"ace":
			for i in 26:
				var dir2 := Vector2.from_angle(_rng.randf() * TAU)
				_add({"kind":"star", "p":ac, "v":dir2 * _rng.randf_range(120.0, 300.0), "life":_rng.randf_range(0.6, 1.1),
					"size":_rng.randf_range(4.0, 8.0), "col":Color(0.75, 0.92, 1.0), "g":0.0, "spin":_rng.randf_range(-6.0, 6.0)})

func _sparks(c: Vector2, n: int, col: Color, sp: float) -> void:
	for i in n:
		var dir := Vector2.from_angle(_rng.randf() * TAU)
		_add({"kind":"spark", "p":c + dir * 20.0, "v":dir * _rng.randf_range(sp * 0.4, sp), "life":_rng.randf_range(0.45, 0.9),
			"size":_rng.randf_range(2.5, 4.5), "col":col, "g":180.0})

func _ember(ar: Rect2, col: Color) -> void:
	var p := Vector2(_rng.randf_range(ar.position.x + ar.size.x * 0.1, ar.end.x - ar.size.x * 0.1), _rng.randf_range(ar.position.y + ar.size.y * 0.4, ar.end.y))
	_add({"kind":"ember", "p":p, "v":Vector2(_rng.randf_range(-20.0, 20.0), _rng.randf_range(-90.0, -40.0)), "life":_rng.randf_range(1.0, 1.8),
		"size":_rng.randf_range(2.5, 4.5), "col":col, "g":-10.0})

func _coin(c: Vector2, sp: float) -> void:
	var dir := Vector2.from_angle(-PI * 0.5 + _rng.randf_range(-1.1, 1.1))
	_add({"kind":"coin", "p":c, "v":dir * _rng.randf_range(sp * 0.5, sp), "life":_rng.randf_range(1.1, 1.6), "size":_rng.randf_range(16.0, 24.0),
		"col":Color.WHITE, "g":700.0, "spin":_rng.randf_range(-8.0, 8.0)})

func _confetti(top := false) -> void:
	var cols := [Color("#ffd65a"), Color("#fff3c4"), Color("#c77dff"), Color("#ff6a5a")]
	var p := Vector2(_rng.randf_range(0.0, size.x), _rng.randf_range(-40.0, 0.0) if top else -10.0)
	_add({"kind":"confetti", "p":p, "v":Vector2(_rng.randf_range(-30.0, 30.0), _rng.randf_range(80.0, 170.0)), "life":_rng.randf_range(2.4, 3.6),
		"size":_rng.randf_range(4.0, 7.0), "col":cols[_rng.randi() % cols.size()], "g":30.0, "spin":_rng.randf_range(-7.0, 7.0)})

func _add(p: Dictionary) -> void:
	p["age"] = 0.0
	p["rot"] = _rng.randf() * TAU
	if parts.size() < 220:
		parts.append(p)

func _step_parts(dt: float) -> void:
	# the effects that go on while it shows: FIRST BLOOD's drips, PENTAKILL's confetti, embers
	if not cur.is_empty() and age < float(cur.life) - OUT:
		var st := str(cur.style)
		_drip_t -= dt
		if _drip_t <= 0.0:
			var ar := art_rect()
			match st:
				"first_blood":
					_drip_t = 0.09
					_add({"kind":"drip", "p":Vector2(_rng.randf_range(ar.position.x + ar.size.x * 0.12, ar.end.x - ar.size.x * 0.12), ar.end.y - ar.size.y * 0.16),
						"v":Vector2(0.0, _rng.randf_range(10.0, 40.0)), "life":_rng.randf_range(0.8, 1.3), "size":_rng.randf_range(2.0, 3.5),
						"col":Color(0.75, 0.03, 0.06), "g":380.0})
				"penta":
					_drip_t = 0.05
					_confetti()
				"triple", "shutdown":
					_drip_t = 0.12
					_ember(ar, Color(1.0, 0.7, 0.25) if st == "triple" else Color(1.0, 0.45, 0.12))
				"quadra":
					_drip_t = 0.1
					_sparks(ar.get_center() + Vector2(_rng.randf_range(-90.0, 90.0), _rng.randf_range(-60.0, 60.0)), 2, Color(1.0, 0.88, 0.45), 120.0)
				_:
					_drip_t = 99.0
	for i in range(parts.size() - 1, -1, -1):
		var p: Dictionary = parts[i]
		p.age = float(p.age) + dt
		if float(p.age) >= float(p.life):
			parts.remove_at(i)
			continue
		p.v = (p.v as Vector2) + Vector2(0.0, float(p.g)) * dt
		if str(p.kind) in ["confetti", "ember"]:
			p.v = (p.v as Vector2) * (1.0 - 0.6 * dt)
		p.p = (p.p as Vector2) + (p.v as Vector2) * dt
		p.rot = float(p.rot) + float(p.get("spin", 0.0)) * dt

func _draw_part(p: Dictionary) -> void:
	var k := 1.0 - float(p.age) / float(p.life)
	var col: Color = p.col
	var pos: Vector2 = p.p
	var sz := float(p.size)
	match str(p.kind):
		"blood", "drip":
			col.a = clampf(k * 1.6, 0.0, 1.0)
			var v: Vector2 = p.v
			_front.draw_line(pos, pos - v.normalized() * sz * 1.8, col, sz * 1.4, true)
			_front.draw_circle(pos, sz, col)
		"spark":
			col.a = k
			_front.draw_circle(pos, sz * 2.2, Color(col.r, col.g, col.b, 0.22 * k))
			_front.draw_line(pos, pos - (p.v as Vector2) * 0.04, col, sz, true)
		"ember":
			col.a = k * (0.6 + 0.4 * sin(float(p.age) * 20.0 + sz))
			_front.draw_circle(pos, sz * 2.0, Color(col.r, col.g, col.b, col.a * 0.25))
			_front.draw_circle(pos, sz, col)
		"coin":
			var t := tex("res://assets/ui/currency/coin.png")
			var sx := absf(cos(float(p.rot))) * 0.8 + 0.2
			if t != null:
				_front.draw_set_transform(pos, 0.0, Vector2(sx, 1.0))
				_front.draw_texture_rect(t, Rect2(-Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, Color(1, 1, 1, clampf(k * 2.0, 0.0, 1.0)))
				_front.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"confetti":
			col.a = clampf(k * 2.0, 0.0, 1.0)
			_front.draw_set_transform(pos, float(p.rot), Vector2(1.0, absf(sin(float(p.rot) * 1.3)) * 0.8 + 0.2))
			_front.draw_rect(Rect2(-Vector2(sz, sz * 0.6) * 0.5, Vector2(sz, sz * 0.6)), col)
			_front.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"star":
			col.a = k
			_front.draw_set_transform(pos, float(p.rot), Vector2.ONE)
			_front.draw_rect(Rect2(Vector2(-sz, -sz * 0.18), Vector2(sz * 2.0, sz * 0.36)), col)
			_front.draw_rect(Rect2(Vector2(-sz * 0.18, -sz), Vector2(sz * 0.36, sz * 2.0)), col)
			_front.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
