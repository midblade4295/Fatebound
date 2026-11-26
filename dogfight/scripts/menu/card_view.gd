class_name CardView
extends Control
## One beveled card tile, drawn entirely in code: rarity frame (Common blue,
## Rare orange, Epic purple, Legendary animated rainbow), category strip, glyph,
## level pill and a copies bar that turns green when an upgrade is affordable.
## Also used for loadout slots, where it can show "empty" or "locked".

signal pressed(view: CardView)

const CARD_SIZE: Vector2 = Vector2(214.0, 268.0)
const CORNER: float = 20.0
const TAP_SLOP: float = 18.0

var card: ComponentCard
var level: int = 0
var copies: int = 0
var owned: bool = false
var equipped: bool = false
var upgrade_ready: bool = false
var selected: bool = false: set = _set_selected
## Text shown when there is no card (loadout slot name).
var empty_title: String = ""
## > 0 draws a padlock message: "Commander Lv N".
var locked_until_level: int = 0
## Loadout slot this tile represents, or -1 for a collection card.
var slot_index: int = -1

var _press_position: Vector2 = Vector2.ZERO
var _pressing: bool = false
var _time: float = 0.0


func _ready() -> void:
	custom_minimum_size = CARD_SIZE
	# PASS lets a drag that starts on a card still scroll the collection.
	mouse_filter = Control.MOUSE_FILTER_PASS


func _process(delta: float) -> void:
	# Only legendary frames animate; everything else redraws on demand.
	if card != null and card.rarity == ComponentCard.Rarity.LEGENDARY and is_visible_in_tree():
		_time += delta
		queue_redraw()


func show_card(new_card: ComponentCard, card_level: int, card_copies: int, is_owned: bool, is_equipped: bool, can_upgrade: bool) -> void:
	card = new_card
	level = card_level
	copies = card_copies
	owned = is_owned
	equipped = is_equipped
	upgrade_ready = can_upgrade
	locked_until_level = 0
	queue_redraw()


func show_empty(title: String, unlock_level: int = 0) -> void:
	card = null
	empty_title = title
	locked_until_level = unlock_level
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if button.pressed:
		_pressing = true
		_press_position = button.position
	elif _pressing:
		_pressing = false
		# A release far from the press was a scroll drag, not a tap.
		if button.position.distance_to(_press_position) <= TAP_SLOP:
			pressed.emit(self)


func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2(4.0, 4.0), size - Vector2(8.0, 12.0))
	if card == null:
		_draw_empty(rect)
		return
	var frame_color: Color = card.rarity_color()
	var face: StyleBoxFlat = StyleBoxFlat.new()
	face.bg_color = UiStyle.NAVY_LIGHT if owned else Color(0.16, 0.18, 0.24)
	face.set_corner_radius_all(int(CORNER))
	face.border_color = UiStyle.OUTLINE
	face.set_border_width_all(4)
	face.border_width_bottom = 10
	draw_style_box(face, Rect2(rect.position, rect.size + Vector2(0.0, 6.0)))

	# Rarity frame.
	var outline: PackedVector2Array = _rounded_outline(rect.grow(-7.0), CORNER - 6.0)
	if card.rarity == ComponentCard.Rarity.LEGENDARY:
		var colors: PackedColorArray = PackedColorArray()
		for index: int in range(outline.size()):
			colors.append(Color.from_hsv(fposmod(float(index) / float(outline.size()) + _time * 0.25, 1.0), 0.7, 1.0))
		draw_polyline_colors(outline, colors, 7.0, true)
	else:
		draw_polyline(outline, frame_color if owned else frame_color.darkened(0.5), 7.0, true)

	# Category strip.
	UiStyle.draw_outlined_text(self, card.category_name().to_upper(), rect.position + Vector2(0.0, 62.0), 18, frame_color.lightened(0.35), rect.size.x, 5)

	# Glyph medallion.
	var medallion: Vector2 = rect.position + Vector2(rect.size.x * 0.5, 116.0)
	draw_circle(medallion, 46.0, UiStyle.OUTLINE)
	draw_circle(medallion, 41.0, frame_color.darkened(0.25) if owned else Color(0.3, 0.32, 0.38))
	draw_circle(medallion - Vector2(0.0, 8.0), 30.0, Color(1.0, 1.0, 1.0, 0.12))
	UiStyle.draw_outlined_text(self, card.glyph, medallion + Vector2(-60.0, 11.0), 30, UiStyle.WHITE, 120.0, 7)

	# Name (two short lines at most).
	var font: Font = ThemeDB.fallback_font
	var name_position: Vector2 = rect.position + Vector2(10.0, 184.0)
	draw_multiline_string_outline(font, name_position, card.display_name, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 20.0, 20, 2, 5, UiStyle.OUTLINE)
	draw_multiline_string(font, name_position, card.display_name, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 20.0, 20, 2, UiStyle.WHITE)

	if owned:
		_draw_level_pill(rect)
		_draw_copies_bar(rect)
	else:
		UiStyle.draw_outlined_text(self, "NOT FOUND", rect.position + Vector2(0.0, rect.size.y - 14.0), 20, Color(0.7, 0.74, 0.82), rect.size.x, 5)
	if equipped:
		var tag: Rect2 = Rect2(rect.position + Vector2(rect.size.x - 78.0, 8.0), Vector2(70.0, 26.0))
		draw_rect(tag, UiStyle.GREEN.darkened(0.2))
		UiStyle.draw_outlined_text(self, "IN USE", tag.position + Vector2(0.0, 20.0), 15, UiStyle.WHITE, tag.size.x, 4)
	if selected:
		draw_polyline(_rounded_outline(rect.grow(2.0), CORNER + 2.0), UiStyle.GOLD, 6.0, true)


func _draw_level_pill(rect: Rect2) -> void:
	var pill: StyleBoxFlat = StyleBoxFlat.new()
	pill.bg_color = UiStyle.OUTLINE
	pill.set_corner_radius_all(12)
	draw_style_box(pill, Rect2(rect.position + Vector2(10.0, 8.0), Vector2(72.0, 28.0)))
	var maxed: bool = card.is_max_level(level)
	UiStyle.draw_outlined_text(self, "MAX" if maxed else "LV %d" % level, rect.position + Vector2(10.0, 29.0), 19,
			UiStyle.GOLD if maxed else UiStyle.WHITE, 72.0, 4)


func _draw_copies_bar(rect: Rect2) -> void:
	var needed: int = card.copies_required(level)
	var bar: Rect2 = Rect2(rect.position + Vector2(16.0, rect.size.y - 36.0), Vector2(rect.size.x - 32.0, 22.0))
	draw_rect(bar.grow(3.0), UiStyle.OUTLINE)
	if needed <= 0:
		draw_rect(bar, UiStyle.GOLD_DARK)
		UiStyle.draw_outlined_text(self, "MAX LEVEL", bar.position + Vector2(0.0, 18.0), 17, UiStyle.WHITE, bar.size.x, 4)
		return
	var fill: float = clampf(float(copies) / float(needed), 0.0, 1.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * fill, bar.size.y)), UiStyle.GREEN if upgrade_ready else UiStyle.XP_CYAN)
	UiStyle.draw_outlined_text(self, "%d / %d" % [copies, needed], bar.position + Vector2(0.0, 18.0), 17, UiStyle.WHITE, bar.size.x, 4)


func _draw_empty(rect: Rect2) -> void:
	var face: StyleBoxFlat = StyleBoxFlat.new()
	face.bg_color = Color(0.08, 0.12, 0.22, 0.75)
	face.set_corner_radius_all(int(CORNER))
	face.border_color = Color(0.45, 0.55, 0.7, 0.8)
	face.set_border_width_all(4)
	draw_style_box(face, rect)
	UiStyle.draw_outlined_text(self, empty_title.to_upper(), rect.position + Vector2(0.0, 46.0), 22, Color(0.75, 0.85, 1.0), rect.size.x, 5)
	if locked_until_level > 0:
		UiStyle.draw_outlined_text(self, "LOCKED", rect.position + Vector2(0.0, rect.size.y * 0.5 + 4.0), 30, Color(0.8, 0.82, 0.88), rect.size.x, 6)
		UiStyle.draw_outlined_text(self, "Commander Lv %d" % locked_until_level, rect.position + Vector2(0.0, rect.size.y * 0.5 + 40.0), 20, UiStyle.GOLD, rect.size.x, 5)
	else:
		UiStyle.draw_outlined_text(self, "+", rect.position + Vector2(0.0, rect.size.y * 0.5 + 26.0), 72, Color(0.6, 0.72, 0.9), rect.size.x, 6)
		UiStyle.draw_outlined_text(self, "EMPTY", rect.position + Vector2(0.0, rect.size.y - 24.0), 20, Color(0.7, 0.78, 0.9), rect.size.x, 5)
	if selected:
		draw_polyline(_rounded_outline(rect.grow(2.0), CORNER + 2.0), UiStyle.GOLD, 6.0, true)


## Closed polyline tracing a rounded rectangle (for frames with per-point colour).
func _rounded_outline(rect: Rect2, radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	var corners: Array[Vector2] = [
		rect.position + Vector2(rect.size.x - radius, radius),
		rect.position + Vector2(rect.size.x - radius, rect.size.y - radius),
		rect.position + Vector2(radius, rect.size.y - radius),
		rect.position + Vector2(radius, radius),
	]
	for corner: int in range(4):
		var start: float = -PI * 0.5 + PI * 0.5 * float(corner)
		for step: int in range(7):
			points.append(corners[corner] + Vector2.from_angle(start + PI * 0.5 * float(step) / 6.0) * radius)
	points.append(points[0])
	return points


func _set_selected(value: bool) -> void:
	if selected != value:
		selected = value
		queue_redraw()
