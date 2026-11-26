class_name UiStyle
extends RefCounted
## One place for the chunky, beveled "Clash" UI look: rounded panels with a
## thick outline and a heavier bottom edge, outlined bold text, candy buttons.
## Everything is built from StyleBoxFlat so there are no texture dependencies.

const NAVY: Color = Color("16233f")
const NAVY_LIGHT: Color = Color("24365e")
const OUTLINE: Color = Color("0b1326")
const GOLD: Color = Color("ffd23f")
const GOLD_DARK: Color = Color("c98a12")
const GREEN: Color = Color("57d04a")
const WHITE: Color = Color("f7fbff")
const HP_GREEN: Color = Color("6be05a")
const XP_CYAN: Color = Color("42d8ff")


## Rounded panel with a dark outline and a thicker "shelf" along the bottom.
static func panel(background: Color, radius: int = 20, border: Color = OUTLINE, border_width: int = 4, padding: int = 12) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.border_width_bottom = border_width * 2
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(float(padding))
	style.anti_aliasing = true
	return style


## Applies a glossy candy-button look (normal / hover / pressed / disabled).
static func style_button(button: Button, color: Color, font_size: int = 34) -> void:
	var normal: StyleBoxFlat = panel(color, 22, color.darkened(0.55), 4, 14)
	var hover: StyleBoxFlat = panel(color.lightened(0.12), 22, color.darkened(0.55), 4, 14)
	var pressed: StyleBoxFlat = panel(color.darkened(0.18), 22, color.darkened(0.6), 4, 14)
	pressed.border_width_bottom = 4
	pressed.content_margin_top = 18.0
	var disabled: StyleBoxFlat = panel(Color(0.42, 0.45, 0.52), 22, Color(0.2, 0.22, 0.27), 4, 14)
	button.add_theme_stylebox_override(&"normal", normal)
	button.add_theme_stylebox_override(&"hover", hover)
	button.add_theme_stylebox_override(&"pressed", pressed)
	button.add_theme_stylebox_override(&"disabled", disabled)
	button.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	button.add_theme_font_size_override(&"font_size", font_size)
	button.add_theme_color_override(&"font_color", WHITE)
	button.add_theme_color_override(&"font_hover_color", WHITE)
	button.add_theme_color_override(&"font_pressed_color", WHITE)
	button.add_theme_color_override(&"font_outline_color", OUTLINE)
	button.add_theme_constant_override(&"outline_size", 8)


## Bold outlined label text.
static func style_label(label: Label, font_size: int, color: Color = WHITE, outline_size: int = 8) -> void:
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", OUTLINE)
	label.add_theme_constant_override(&"outline_size", outline_size)


## Chunky progress bar (HP, XP, card copies).
static func style_bar(bar: ProgressBar, fill: Color, height: float = 22.0) -> void:
	var background: StyleBoxFlat = StyleBoxFlat.new()
	background.bg_color = OUTLINE
	background.set_corner_radius_all(8)
	background.set_border_width_all(3)
	background.border_color = OUTLINE
	var foreground: StyleBoxFlat = StyleBoxFlat.new()
	foreground.bg_color = fill
	foreground.set_corner_radius_all(6)
	foreground.set_border_width_all(3)
	foreground.border_color = OUTLINE
	bar.add_theme_stylebox_override(&"background", background)
	bar.add_theme_stylebox_override(&"fill", foreground)
	bar.show_percentage = false
	bar.custom_minimum_size.y = height


## Text with an outline, for custom-drawn controls. [param position] is the
## baseline-left corner unless [param centered_width] > 0, which centres the
## text in that width.
static func draw_outlined_text(canvas: CanvasItem, text: String, position: Vector2, font_size: int,
		color: Color = WHITE, centered_width: float = -1.0, outline_size: int = 6) -> void:
	var font: Font = ThemeDB.fallback_font
	var alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER if centered_width > 0.0 else HORIZONTAL_ALIGNMENT_LEFT
	canvas.draw_string_outline(font, position, text, alignment, centered_width, font_size, outline_size, OUTLINE)
	canvas.draw_string(font, position, text, alignment, centered_width, font_size, color)
