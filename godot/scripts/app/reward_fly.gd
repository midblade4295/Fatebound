extends Node2D
# Currency gains fly into their counters (0.31.105, Kevin: "when a player obtains them it'll play a animation where they
# fly to the players total amount at top of screen"). A burst of the new Meshy coins / diamonds / embers (pre-rendered
# turning, assets/ui/currency/*_spin.png from tools/render_currency_icons.gd) pops out of where the reward came from,
# then each piece curves up into its counter in the top bar; the counter counts up as they land. Lives on a CanvasLayer
# above everything (modals too). siege_app.gd decides when (a rise in the profile's gold / gems / embers).
const FRAMES := 16
const SIZE := 58.0                     # a piece's height in flight (px)
const KINDS := {
	"coin": {"spin": "res://assets/ui/currency/coin_spin.png", "fps": 20.0, "spark": Color(1.0, 0.86, 0.38),
		"glow": Color(1.0, 0.78, 0.3, 0.5), "rise": 0.0},
	"gem": {"spin": "res://assets/ui/currency/gem_spin.png", "fps": 10.0, "spark": Color(0.7, 0.95, 1.0),
		"glow": Color(0.35, 0.8, 1.0, 0.55), "rise": 0.0},
	"ember": {"spin": "res://assets/ui/currency/ember_spin.png", "fps": 14.0, "spark": Color(1.0, 0.55, 0.15),
		"glow": Color(1.0, 0.42, 0.08, 0.75), "rise": -90.0},
}
var flying := 0                        # pieces in the air (tests)
var bursts := 0                        # bursts started (tests)
var _dot: Texture2D
var _sparkle: Texture2D
var _flame: Texture2D
var _add_mat: CanvasItemMaterial
var _sheets := {}
var _t := 0.0

func _ready() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	_dot = gt
	_sparkle = load("res://assets/vfx/weapon/sparkle.png") if ResourceLoader.exists("res://assets/vfx/weapon/sparkle.png") else _dot
	_flame = load("res://assets/vfx/weapon/flame.png") if ResourceLoader.exists("res://assets/vfx/weapon/flame.png") else null
	_add_mat = CanvasItemMaterial.new()
	_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

static func pieces_for(amount: int) -> int:
	# a few for a little, a dozen for a lot
	return clampi(int(round(2.0 + log(float(maxi(amount, 1)) + 1.0) / log(2.0) * 1.1)), 3, 12)

func burst(kind: String, amount: int, from: Vector2, target: Control, land: Callable, done: Callable) -> void:
	# land(share) as each piece reaches the counter (the shares add up to amount); done() after the last
	var n := pieces_for(amount)
	var shares: Array = []
	for i in n:
		shares.append(amount / n + (1 if i < amount % n else 0))
	bursts += 1
	var left := [n]
	for i in n:
		_piece(kind, from, target, i, func():
			land.call(int(shares[i]))
			left[0] -= 1
			if left[0] == 0:
				done.call())

func _sheet(kind: String) -> Texture2D:
	if not _sheets.has(kind):
		var p: String = KINDS[kind].spin
		_sheets[kind] = load(p) if ResourceLoader.exists(p) else null
	return _sheets[kind]

func _target_point(target: Control, fallback: Vector2) -> Vector2:
	return target.get_global_rect().get_center() if is_instance_valid(target) and target.is_visible_in_tree() else fallback

func _piece(kind: String, from: Vector2, target: Control, i: int, arrived: Callable) -> void:
	var spec: Dictionary = KINDS[kind]
	var s := Sprite2D.new()
	var sheet := _sheet(kind)
	if sheet != null:
		s.texture = sheet
		s.hframes = FRAMES
		s.frame = randi() % FRAMES
	else:
		s.texture = load("res://assets/ui/currency/%s.png" % ("coin" if kind == "coin" else kind))
	var base := SIZE / float(s.texture.get_height())
	s.scale = Vector2.ONE * base * 0.2
	s.position = from
	s.visible = false
	s.set_meta("fps", float(spec.fps) * randf_range(0.8, 1.25))
	s.set_meta("f0", randf() * FRAMES)
	add_child(s)
	flying += 1
	var halo := Sprite2D.new()                  # a soft glow round the piece
	halo.texture = _dot
	halo.material = _add_mat
	halo.modulate = spec.glow
	halo.scale = Vector2.ONE * (SIZE * 1.5 / 64.0) / base
	halo.show_behind_parent = true
	s.add_child(halo)
	if kind == "ember" and _flame != null:        # the ember's flame (the concept's; not in the model)
		var fl := Sprite2D.new()
		fl.texture = _flame
		fl.material = _add_mat
		fl.modulate = Color(1.0, 0.55, 0.15, 0.95)
		fl.offset = Vector2(0, -_flame.get_height() * 0.42)
		fl.position = Vector2(0, -s.texture.get_height() * 0.18)
		fl.scale = Vector2.ONE * (SIZE * 0.9 / float(_flame.get_height())) / base
		fl.set_meta("flame", fl.scale)
		s.add_child(fl)
	var sp := CPUParticles2D.new()              # a short trail of sparks
	sp.texture = _dot if kind == "ember" else _sparkle
	sp.material = _add_mat
	sp.local_coords = false
	sp.amount = 14
	sp.lifetime = 0.42
	sp.emitting = false
	sp.direction = Vector2(0, 1)
	sp.spread = 180.0
	sp.initial_velocity_min = 10.0
	sp.initial_velocity_max = 40.0
	sp.gravity = Vector2(0, float(spec.rise))
	var ts := 64.0 / float(sp.texture.get_width())   # (sizes for the 64 px dot)
	sp.scale_amount_min = 0.06 * ts * (1.6 if kind != "ember" else 1.0)
	sp.scale_amount_max = 0.16 * ts * (1.6 if kind != "ember" else 1.0)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(spec.spark, 1.0))
	ramp.set_color(1, Color(spec.spark, 0.0))
	sp.color_ramp = ramp
	add_child(sp)
	# out of the reward in a burst, then up into the counter on a curve
	var out_dir := Vector2.from_angle(randf_range(-PI * 0.92, -PI * 0.08))
	var p1 := from + out_dir * randf_range(55.0, 125.0)
	var bend := randf_range(-1.0, 1.0) * 110.0
	var t_out := randf_range(0.22, 0.3)
	var t_home := randf_range(0.48, 0.62)
	var tw := create_tween()
	tw.tween_interval(i * 0.055)
	tw.tween_callback(func():
		s.visible = true
		sp.position = s.position
		sp.emitting = true)
	tw.tween_method(func(t: float):
		var e := 1.0 - pow(1.0 - t, 3.0)
		s.position = from.lerp(p1, e)
		s.scale = Vector2.ONE * base * lerpf(0.25, 1.0, e)
		sp.position = s.position, 0.0, 1.0, t_out)
	tw.tween_method(func(t: float):
		var p3 := _target_point(target, Vector2(get_viewport_rect().size.x * 0.75, 30.0))
		var mid := (p1 + p3) * 0.5
		var perp := (p3 - p1).orthogonal().normalized()
		var c := mid + perp * bend + Vector2(0, -50)
		var e := t * t
		s.position = p1.lerp(c, e).lerp(c.lerp(p3, e), e)
		s.scale = Vector2.ONE * base * lerpf(1.0, 0.55, e)
		sp.position = s.position, 0.0, 1.0, t_home)
	tw.tween_callback(func():
		flying -= 1
		sp.emitting = false
		_flash(s.position, spec.glow)
		s.queue_free()
		var kill := sp.create_tween()             # let the last sparks fade, then go
		kill.tween_interval(sp.lifetime + 0.05)
		kill.tween_callback(sp.queue_free)
		arrived.call())

func _flash(at: Vector2, col: Color) -> void:
	var f := Sprite2D.new()
	f.texture = _dot
	f.material = _add_mat
	f.modulate = Color(col, 0.9)
	f.position = at
	f.scale = Vector2.ONE * 0.5
	add_child(f)
	var tw := f.create_tween().set_parallel()
	tw.tween_property(f, "scale", Vector2.ONE * 1.4, 0.25).set_ease(Tween.EASE_OUT)
	tw.tween_property(f, "modulate:a", 0.0, 0.25)
	tw.chain().tween_callback(f.queue_free)

func _process(delta: float) -> void:
	_t += delta
	for c in get_children():
		if not (c is Sprite2D and c.has_meta("fps")):
			continue
		if (c as Sprite2D).hframes == FRAMES:
			(c as Sprite2D).frame = int(float(c.get_meta("f0")) + _t * float(c.get_meta("fps"))) % FRAMES
		for f in c.get_children():
			if f.has_meta("flame"):                   # the flame flickers and stays upright while the ember tumbles
				var k := float(c.get_meta("f0"))
				var b: Vector2 = f.get_meta("flame")
				(f as Sprite2D).scale = b * Vector2(1.0 + 0.12 * sin(_t * 23.0 + k), 1.0 + 0.2 * sin(_t * 17.0 + k * 2.0))
