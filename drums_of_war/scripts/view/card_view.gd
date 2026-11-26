extends Control
## One card in the hand, as a node that animates itself.
##
## The battle screen owns the rules and the input; it tells a card what it is and what state it
## is in, and the card does the feel:
##   deal()            slides in from the NEXT slot, growing to full size
##   set_affordable()  a quick swell and a flash of halo the moment Powder first covers the cost
##   set_selected()    lifts clear of the tray
##   begin_drag() / drag_to() / end_drag()
##                     follows the finger, tilts with its sideways speed, shrinks as it leaves
##                     the tray, and its shadow drops away and spreads the higher it is held
##
## It draws with the shared kit (ui_kit.gd). Its rect is its resting place in the tray; while it
## is being dragged or dealt it draws away from that rect, which Godot allows.

const Kit = preload("res://scripts/view/ui_kit.gd")

var kit: Kit
var card_id: String = ""
var def: Dictionary = {}
var art: Texture2D
var affordable: bool = false
var selected: bool = false
var dragging: bool = false

# What the tweens animate. All are read in _draw().
var lift: float = 0.0            # pixels raised above the resting place
var tilt: float = 0.0            # radians
var swell: float = 1.0           # scale pulse
var shrink: float = 1.0          # scale while dragged over the field, or while being dealt
var offset: Vector2 = Vector2.ZERO   # displacement from the resting place
var halo: float = 0.0            # amber glow, 0..1
var fade: float = 1.0

var _drawn: int = 0
var _moves: Tween
var _pulse: Tween
var _lift_tween: Tween
var _grab: Vector2 = Vector2.ZERO
var _speed_x: float = 0.0
var _last_pointer: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE          # the battle screen reads the input
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


func _process(_delta: float) -> void:
	# Redraw only when something about the card's look has changed: most frames nothing has.
	var glint := Time.get_ticks_msec() / 40 if def.get("rarity", "") == "legendary" else 0     # its frame glints
	var now := hash([card_id, affordable, selected, dragging, lift, tilt, swell, shrink, offset, halo, fade, size, glint])
	if now != _drawn:
		_drawn = now
		queue_redraw()


func _restart(old: Tween) -> Tween:
	if old != null and old.is_valid():
		old.kill()
	return create_tween()


## Becomes a new card and slides in from where the NEXT card sits (a rect in the same space as
## this node's parent), after an optional delay so a fresh hand deals out one card at a time.
func deal(new_id: String, new_def: Dictionary, new_art: Texture2D, from: Rect2, delay: float = 0.0) -> void:
	card_id = new_id
	def = new_def
	art = new_art
	affordable = false
	selected = false
	dragging = false
	tilt = 0.0
	lift = 0.0
	swell = 1.0
	halo = 0.0
	offset = from.get_center() - (position + size * 0.5)
	shrink = from.size.x / maxf(1.0, size.x)
	fade = 0.0
	_moves = _restart(_moves)
	_moves.set_parallel(true)
	_moves.tween_property(self, "fade", 1.0, 0.1).set_delay(delay)
	_moves.tween_property(self, "offset", Vector2.ZERO, 0.34).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_moves.tween_property(self, "shrink", 1.0, 0.34).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Call every frame with whether Powder covers the cost. The moment it first does, the card
## swells and its halo flashes; while it stays playable a faint halo remains.
func set_affordable(now: bool) -> void:
	if now == affordable or card_id == "":
		return
	affordable = now
	_pulse = _restart(_pulse)
	if now:
		_pulse.tween_property(self, "swell", 1.09, 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_pulse.parallel().tween_property(self, "halo", 1.0, 0.11)
		_pulse.tween_property(self, "swell", 1.0, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_pulse.parallel().tween_property(self, "halo", 0.3, 0.5)
	else:
		_pulse.tween_property(self, "halo", 0.0, 0.18)
		_pulse.parallel().tween_property(self, "swell", 1.0, 0.1)


func set_selected(now: bool) -> void:
	if now == selected:
		return
	selected = now
	if dragging:
		return
	_lift_tween = _restart(_lift_tween)
	_lift_tween.tween_property(self, "lift", 14.0 if now else 0.0, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The finger has started to drag this card. pointer is in the parent's space.
func begin_drag(pointer: Vector2) -> void:
	dragging = true
	_grab = pointer - (position + size * 0.5 + offset)
	_last_pointer = pointer
	_speed_x = 0.0
	if _moves != null and _moves.is_valid():
		_moves.kill()
	_lift_tween = _restart(_lift_tween)
	_lift_tween.tween_property(self, "lift", 26.0, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Call every frame while dragging. over_field says the finger is above the tray, on the arena.
func drag_to(pointer: Vector2, over_field: bool, delta: float) -> void:
	if not dragging:
		return
	var want := pointer - _grab - (position + size * 0.5)
	offset = offset.lerp(want, 1.0 - exp(-32.0 * delta))
	# Tilt into the direction of travel, like a card held by its top edge.
	var vx := (pointer.x - _last_pointer.x) / maxf(delta, 0.001)
	_last_pointer = pointer
	_speed_x = lerpf(_speed_x, vx, 1.0 - exp(-14.0 * delta))
	tilt = lerpf(tilt, clampf(_speed_x * 0.0011, -0.3, 0.3), 1.0 - exp(-16.0 * delta))
	# Over the arena the card gets out of the way of what it is about to place.
	shrink = lerpf(shrink, 0.6 if over_field else 1.0, 1.0 - exp(-14.0 * delta))


## The drag is over. A played card pops away (the screen then deals its replacement); one that
## was not played springs back to its place.
func end_drag(played: bool) -> void:
	if not dragging:
		return
	dragging = false
	_moves = _restart(_moves)
	_moves.set_parallel(true)
	if played:
		_moves.tween_property(self, "shrink", 0.25, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_moves.tween_property(self, "fade", 0.0, 0.12)
	else:
		_moves.tween_property(self, "offset", Vector2.ZERO, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_moves.tween_property(self, "shrink", 1.0, 0.2)
		_moves.tween_property(self, "tilt", 0.0, 0.2)
		_moves.tween_property(self, "lift", 14.0 if selected else 0.0, 0.2)


func _draw() -> void:
	if kit == null or card_id == "" or fade <= 0.01:
		return
	modulate.a = fade
	var centre := size * 0.5 + offset + Vector2(0, -lift)
	var scale_now := swell * shrink
	var face := Rect2(-size * 0.5, size)
	# Shadow: the higher the card is held, the further it falls away, the wider it spreads and
	# the fainter it gets.
	var height := lift + (30.0 if dragging else 0.0)
	var spread := 1.0 + height * 0.006
	draw_set_transform(centre + Vector2(height * 0.12, 6.0 + height * 0.55), tilt, Vector2.ONE * scale_now * spread)
	var shadow_key := "card_shadow_high" if height > 20.0 else ("card_shadow_mid" if height > 6.0 else "card_shadow_low")
	var alpha := 0.3 if height > 20.0 else (0.42 if height > 6.0 else 0.55)
	var soft := 16.0 if height > 20.0 else (11.0 if height > 6.0 else 7.0)
	draw_style_box(kit.box(shadow_key, Color(0, 0, 0, alpha * 0.6), 9.0, 0.0, Color.BLACK, soft, Color(0, 0, 0, alpha)), face.grow(1.0))
	draw_set_transform(centre, tilt, Vector2.ONE * scale_now)
	var glow := maxf(halo, 1.0 if (selected or dragging) else 0.0)
	kit.card_face(self, face, def, art, affordable, glow)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
