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
const Tactile = preload("res://scripts/ui/tactile_style.gd")

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

static func button(bg: Color = RAISED, stroke: Color = GOLD_DARK, radius: int = 11) -> StyleBox:
    # Kept for existing call sites: any "button" is now a dimensional tactile face in these colours.
    return tactile_from(bg, stroke, radius)

static func tactile_from(bg: Color, stroke: Color, radius: int = 11, state := "normal") -> StyleBox:
    var style: StyleBox = Tactile.new()
    style.top = bg.lightened(0.16)
    style.bottom = bg.darkened(0.22)
    style.lip = bg.darkened(0.62)
    style.rim = stroke
    style.radius = radius
    style.depth = 4.0
    style.pressed = state == "pressed"
    style.content_margin_left = 10
    style.content_margin_right = 10
    style.content_margin_top = 5 + (3 if state == "pressed" else 0)
    style.content_margin_bottom = 9 - (3 if state == "pressed" else 0)
    if state == "hover":
        style.top = style.top.lightened(0.08)
        style.gloss = 0.28
    if state == "disabled":
        style.gloss = 0.08
    return style

# Named palettes for the whole game. "primary" is the molten-orange ROLL, "gold" the home CTA,
# "secondary" the navy/gold standard control, "active" a lit cyan toggle, "arcane" spells/ultimate.
const PALETTES := {
    "primary": {"top":"#ffb24a","bottom":"#e2571a","lip":"#7c2a07","rim":"#ffe6a6","glow":"#ff9a3a","text":"#fffaf0"},
    "gold": {"top":"#ffd875","bottom":"#c98612","lip":"#6b4105","rim":"#fff0b8","glow":"#ffcc55","text":"#2a1604"},
    "secondary": {"top":"#1f3d4d","bottom":"#10232e","lip":"#050d12","rim":"#b3894b","glow":"","text":"#f2d18d"},
    "active": {"top":"#2f8f94","bottom":"#155258","lip":"#062326","rim":"#9ff6ef","glow":"#5ce8e0","text":"#effffd"},
    "arcane": {"top":"#6a4bb0","bottom":"#35226a","lip":"#140a2c","rim":"#d6b8ff","glow":"#a77bff","text":"#f6efff"},
    "disabled": {"top":"#1a2a33","bottom":"#121e25","lip":"#070d11","rim":"#3d4d56","glow":"","text":"#7f9097"},
}

static func tactile(kind: String, state := "normal", radius := 12) -> StyleBox:
    var pal: Dictionary = PALETTES.get("disabled" if state == "disabled" else kind, PALETTES.secondary)
    var style: StyleBox = Tactile.new()
    style.top = Color(pal.top)
    style.bottom = Color(pal.bottom)
    style.lip = Color(pal.lip)
    style.rim = Color(pal.rim)
    style.radius = radius
    style.depth = 5.0 if kind in ["primary","gold"] else 4.0
    style.pressed = state == "pressed"
    if not str(pal.glow).is_empty() and state != "disabled":
        style.glow = Color(pal.glow)
        style.glow.a = 0.55 if state == "hover" else 0.38
    if state == "hover":
        style.top = style.top.lightened(0.10)
        style.bottom = style.bottom.lightened(0.05)
        style.gloss = 0.3
    elif state == "pressed":
        style.top = style.top.darkened(0.06)
        style.gloss = 0.14
    elif state == "disabled":
        style.gloss = 0.06
    var d: float = style.depth
    style.content_margin_left = 10
    style.content_margin_right = 10
    style.content_margin_top = 4 + (d - 1 if state == "pressed" else 0.0)
    style.content_margin_bottom = d + 4 - (d - 1 if state == "pressed" else 0.0)
    return style

static func apply_tactile(b: Button, kind: String, radius := 12) -> void:
    for state in ["normal","hover","pressed","disabled"]:
        b.add_theme_stylebox_override(state, tactile(kind, state, radius))
    b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
    var pal: Dictionary = PALETTES.get(kind, PALETTES.secondary)
    for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_hover_pressed_color"]:
        b.add_theme_color_override(key, Color(pal.text))
    b.add_theme_color_override("font_disabled_color", Color(PALETTES.disabled.text))
    b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55) if kind != "gold" else Color(1, 0.95, 0.8, 0.35))
    b.add_theme_constant_override("outline_size", 3 if kind in ["primary","active","arcane"] else 0)

static func cta(hover := false) -> StyleBox:
    return tactile("gold", "hover" if hover else "normal", 14)

static func install() -> Theme:
    var ui := Theme.new()
    ui.default_font = BODY_FONT
    ui.default_font_size = 14
    for kind in ["Label", "Button", "OptionButton", "LineEdit", "TextEdit", "RichTextLabel"]:
        ui.set_font("font", kind, BODY_FONT)
        ui.set_color("font_color", kind, TEXT)
    ui.set_font("font", "Button", BOLD_FONT)
    ui.set_font("font", "OptionButton", BOLD_FONT)
    for state in ["normal","hover","pressed","disabled"]:
        ui.set_stylebox(state, "Button", tactile("secondary", state, 11))
    ui.set_stylebox("focus", "Button", StyleBoxEmpty.new())
    ui.set_color("font_color", "Button", GOLD)
    ui.set_color("font_hover_color", "Button", Color("#ffe4a6"))
    ui.set_color("font_pressed_color", "Button", Color("#ffe4a6"))
    ui.set_color("font_disabled_color", "Button", Color("#7f9097"))
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
