extends RefCounted
# One visual language for the native menus and the match HUD.
const BODY_FONT = preload("res://assets/fonts/DejaVuSans.ttf")
const BOLD_FONT = preload("res://assets/fonts/Nunito-ExtraBold.woff2")
const SANS_BOLD_FALLBACK = preload("res://assets/fonts/DejaVuSans-Bold.ttf")
# Cinzel (OFL) for big titles; DejaVu fallbacks supply symbols such as ♛ ✦ ⛨ ◀ that the Latin subsets lack.
const TITLE_FONT = preload("res://assets/fonts/Cinzel-Black.woff2")
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
const Brass = preload("res://scripts/ui/brass_style.gd")
const BRASS_LIGHT := Color("#f0cf82")
const BRASS_DARK := Color("#6f4f1e")

static func ensure_fonts() -> void:
    var bold: Font = BOLD_FONT
    var title: Font = TITLE_FONT
    if bold.fallbacks.is_empty():
        bold.fallbacks = [SANS_BOLD_FALLBACK]
    if title.fallbacks.is_empty():
        title.fallbacks = [DISPLAY_FONT, SANS_BOLD_FALLBACK]

static func panel(bg: Color = SURFACE, stroke: Color = GOLD_DARK, radius: int = 12, padding: int = 12) -> StyleBox:
    # Framed panels get the beveled brass rim; borderless fills (bars, tracks) stay flat.
    if padding > 0 and stroke.a > 0.05:
        var brass: StyleBox = Brass.new()
        brass.top = Color(bg.lightened(0.06), bg.a)
        brass.bottom = Color(bg.darkened(0.35), bg.a)
        var saturated := stroke.s > 0.35 and (stroke.h < 0.06 or stroke.h > 0.18)
        brass.rim_light = stroke.lightened(0.25) if saturated else BRASS_LIGHT
        brass.rim_dark = stroke.darkened(0.45) if saturated else BRASS_DARK
        brass.rim_light.a = maxf(0.6, stroke.a)
        brass.rim_dark.a = maxf(0.6, stroke.a)
        brass.radius = radius
        brass.set_content_margin_all(padding + 2)
        return brass
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
    "roll": {"top":"#f4cf6c","bottom":"#9a6414","lip":"#452a05","rim":"#fff1bf","glow":"#ffcf5a","text":"#fffaf0"},
    "gold": {"top":"#ffd875","bottom":"#c98612","lip":"#6b4105","rim":"#fff0b8","glow":"#ffcc55","text":"#2a1604"},
    "secondary": {"top":"#2c3136","bottom":"#121518","lip":"#040506","rim":"#b8904e","glow":"","text":"#f2d18d"},
    "active": {"top":"#2f8f94","bottom":"#155258","lip":"#062326","rim":"#9ff6ef","glow":"#5ce8e0","text":"#effffd"},
    "arcane": {"top":"#6a4bb0","bottom":"#35226a","lip":"#140a2c","rim":"#d6b8ff","glow":"#a77bff","text":"#f6efff"},
    "nav_active": {"top":"#35404a","bottom":"#141a1f","lip":"#050608","rim":"#ffe09a","glow":"#ffcc55","text":"#ffffff"},
    "disabled": {"top":"#1a2a33","bottom":"#121e25","lip":"#070d11","rim":"#3d4d56","glow":"","text":"#7f9097"},
}

static func tactile(kind: String, state := "normal", radius := 12) -> StyleBox:
    var pal: Dictionary = PALETTES.get("disabled" if state == "disabled" else kind, PALETTES.secondary)
    if state == "disabled" and kind == "arcane":
        pal = {"top":"#3b2f58","bottom":"#221a36","lip":"#0c0816","rim":"#6d5a92","glow":"","text":"#a595c4"}
    var style: StyleBox = Tactile.new()
    style.top = Color(pal.top)
    style.bottom = Color(pal.bottom)
    style.lip = Color(pal.lip)
    style.rim = Color(pal.rim)
    style.radius = radius
    style.depth = 5.0 if kind in ["primary","gold","roll"] else 4.0
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

