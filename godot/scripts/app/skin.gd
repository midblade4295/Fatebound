extends Node2D
# 0.31.79: the menu skin (ui_skin.gdshader) drawn behind its parent Control and sized to it. A Node2D, so containers
# don't lay it out, and show_behind_parent puts it under the parent's own text/stylebox.
const SHADER = preload("res://scripts/app/ui_skin.gdshader")

var pad := 16.0
var mat: ShaderMaterial
var inset := Vector2.ZERO          # shrink the drawn rect on each side (e.g. a raised tab drawn bigger than its button)
var offset_rect := Rect2()         # when size is set, draw this rect instead of the parent's (local coordinates)

func _init(params: Dictionary = {}) -> void:
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	material = mat
	show_behind_parent = true
	for k in params:
		mat.set_shader_parameter(k, params[k])

var _btn: BaseButton = null
var _was_down := false
var _was_off := false

func _ready() -> void:
	var c := get_parent() as Control
	if c != null:
		c.resized.connect(_fit)
	_btn = c as BaseButton
	set_process(_btn != null)
	_fit()

func _process(_d: float) -> void:
	# A button's skin follows it: pushed in while held, greyed while disabled.
	var m := _btn.get_draw_mode()
	var down := m == BaseButton.DRAW_PRESSED or m == BaseButton.DRAW_HOVER_PRESSED
	if down != _was_down:
		_was_down = down
		mat.set_shader_parameter("pressed", 1.0 if down else 0.0)
	if _btn.disabled != _was_off:
		_was_off = _btn.disabled
		mat.set_shader_parameter("dim", 0.55 if _was_off else 0.0)

func set_param(k: String, v: Variant) -> void:
	mat.set_shader_parameter(k, v)

func _rect() -> Rect2:
	if offset_rect.size != Vector2.ZERO:
		return offset_rect
	var c := get_parent() as Control
	var s := c.size if c != null else Vector2(10, 10)
	return Rect2(inset, s - inset * 2.0)

func _fit() -> void:
	var r := _rect()
	position = r.position
	mat.set_shader_parameter("rect_size", r.size)
	queue_redraw()

func _draw() -> void:
	var r := _rect()
	draw_rect(Rect2(Vector2(-pad, -pad), r.size + Vector2(pad * 2.0, pad * 2.0)), Color.WHITE)
