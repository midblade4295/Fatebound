extends RefCounted
# One visual language for the native menus and the match HUD.
const BODY_FONT = preload("res://assets/fonts/DejaVuSans.ttf")
const BOLD_FONT = preload("res://assets/fonts/DejaVuSans-Bold.ttf")
const DISPLAY_FONT = preload("res://assets/fonts/DejaVuSerif-Bold.ttf")
const INK := Color("#06131b")
const SURFACE := Color("#091d27")
const RAISED := Color("#102c37")
const GOLD := Color("#f2d18d")
const GOLD_DARK := Color("#ad8651")
const CYAN := Color("#70d8e2")
const RED := Color("#ed8c68")
const TEXT := Color("#f3efe1")

static func panel(bg: Color = SURFACE, stroke: Color = GOLD_DARK, radius: int = 12, padding: int = 12) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = bg
    style.border_color = stroke
    style.set_border_width_all(1)
    style.border_width_top = 2
    style.set_corner_radius_all(radius)
    style.set_content_margin_all(padding)
    style.shadow_color = Color(0, 0, 0, 0.50)
    style.shadow_size = 7
    style.anti_aliasing = true
    return style

static func button(bg: Color = RAISED, stroke: Color = GOLD_DARK, radius: int = 11) -> StyleBoxFlat:
    var style := panel(bg, stroke, radius, 6)
    style.border_width_top = 2
    style.content_margin_left = 10
    style.content_margin_right = 10
    style.shadow_size = 3
    return style

static func cta(hover := false) -> StyleBoxFlat:
    var style := button(Color("#d58b16") if hover else Color("#a9670d"),Color("#ffdf80"),14)
    style.set_border_width_all(2)
    style.border_width_top = 3
    style.shadow_color = Color("#e8a52d99")
    style.shadow_size = 10 if hover else 8
    style.shadow_offset = Vector2(0,2)
    return style

static func install() -> Theme:
    var ui := Theme.new()
    ui.default_font = BODY_FONT
    ui.default_font_size = 14
    for kind in ["Label", "Button", "OptionButton", "LineEdit", "TextEdit", "RichTextLabel"]:
        ui.set_font("font", kind, BODY_FONT)
        ui.set_color("font_color", kind, TEXT)
    ui.set_font("font", "Button", BOLD_FONT)
    ui.set_font("font", "OptionButton", BOLD_FONT)
    ui.set_stylebox("normal", "Button", button())
    ui.set_stylebox("hover", "Button", button(Color("#254858"), GOLD))
    ui.set_stylebox("pressed", "Button", button(Color("#294c4d"), CYAN))
    ui.set_stylebox("disabled", "Button", button(Color("#172832"), Color("#52616b")))
    ui.set_stylebox("focus", "Button", button(Color.TRANSPARENT, CYAN))
    ui.set_color("font_disabled_color", "Button", Color("#9caaad"))
    for state in ["normal", "hover", "pressed", "disabled", "focus"]:
        ui.set_stylebox(state, "OptionButton", ui.get_stylebox(state, "Button"))
    ui.set_stylebox("panel", "PanelContainer", panel())
    ui.set_stylebox("normal", "LineEdit", panel(INK, GOLD_DARK, 9, 8))
    ui.set_stylebox("focus", "LineEdit", panel(INK, CYAN, 9, 8))
    ui.set_stylebox("normal", "TextEdit", panel(INK, GOLD_DARK, 9, 8))
    ui.set_stylebox("focus", "TextEdit", panel(INK, CYAN, 9, 8))
    ui.set_stylebox("background", "ProgressBar", panel(INK, Color("#27404c"), 5, 0))
    ui.set_stylebox("fill", "ProgressBar", panel(CYAN, CYAN, 5, 0))
    return ui
