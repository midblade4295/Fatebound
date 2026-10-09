extends Control
# "Update required" (0.31.73). Shown over everything when the Siege server speaks a newer protocol than this build
# (Net.version_verdict == "update"). Full screen and input-blocking: the only ways out are UPDATE (the Play Store page)
# and, if ALLOW_OFFLINE, "Play offline vs bots" -- online play stays locked (siege_app.gd re-shows this screen when
# ONLINE / PLAY online is pressed). Android back quits the app instead of dismissing it.
const UI = preload("res://scripts/app/ui.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
const Diag = preload("res://scripts/siege/siege_diag.gd")

const PACKAGE := "com.fatebound.game"
const MARKET_URL := "market://details?id=" + PACKAGE
const WEB_URL := "https://play.google.com/store/apps/details?id=" + PACKAGE
const ALLOW_OFFLINE := true      # false = a hard wall (no offline matches either)
const TITLE := "UPDATE REQUIRED"
const BODY := "A new version of Fatebound is available. Update to keep playing."

signal offline_requested

var server_version := -1
# How URLs are opened (tests replace it). Returns an Error like OS.shell_open.
var open_url: Callable = func(u: String) -> int: return OS.shell_open(u)
var opened: Array = []           # URLs tried, in order (diagnostics / tests)

static func open_store(opener: Callable, tried: Array = []) -> void:
	# The Play Store app first (market://), the web page if that can't be opened (no Play Store, desktop).
	if OS.get_name() == "Android":
		tried.append(MARKET_URL)
		if int(opener.call(MARKET_URL)) == OK:
			return
	tried.append(WEB_URL)
	opener.call(WEB_URL)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP          # nothing underneath can be tapped
	var bg := ColorRect.new()
	bg.color = Color(0.027, 0.043, 0.082, 1.0)       # opaque: nothing of the menu shows through
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	var glow := TextureRect.new()
	var gg := Gradient.new()
	gg.set_color(0, Color(1.0, 0.72, 0.3, 0.20))
	gg.set_color(1, Color(1.0, 0.72, 0.3, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = gg
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 1.0)
	gt.width = 128
	gt.height = 128
	glow.texture = gt
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.anchor_right = 1.0
	glow.anchor_bottom = 0.6
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)
	var icon := UI.tex_icon(col, "res://assets/branding/icon.png", 132)   # the launcher icon (read only)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var title := UI.title(col, TITLE, 30, UI.GOLD)
	title.add_theme_color_override("font_outline_color", Color("#2e1908"))
	title.add_theme_constant_override("outline_size", 8)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var body := UI.label(col, BODY, 18, UI.TEXT)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UI.spacer(col, 10.0)
	var up := UI.button(col, "UPDATE", "primary", _on_update, "update_now", 30, 22)
	up.add_theme_font_override("font", UI.TITLE_FONT)
	up.custom_minimum_size = Vector2(0, 86)
	var sub := UI.label(col, "Opens Fatebound on Google Play", 12, UI.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if ALLOW_OFFLINE:
		UI.spacer(col, 18.0)
		var off := UI.button(col, "PLAY OFFLINE VS BOTS", "ghost", func(): offline_requested.emit(), "update_offline", 14)
		off.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		off.custom_minimum_size = Vector2(240, 46)
		var note := UI.label(col, "Online 16v16 needs the update.", 11, UI.MUTED)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.spacer(col, 10.0)
	var ver := UI.label(col, "Your version: %s (protocol %d)%s" % [_app_version(), Net.VERSION,
		("  ·  server: protocol %d" % server_version) if server_version > 0 else ""], 10, Color(UI.MUTED, 0.75))
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _app_version() -> String:
	var v := str(ProjectSettings.get_setting("application/config/version", ""))
	return v if v != "" else Diag.BUILD

func _on_update() -> void:
	open_store(open_url, opened)
