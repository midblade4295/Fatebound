extends SceneTree
# Font metrics as Godot computes them, for tools/guitest's `fonts` check:
#   godot --headless --path godot -s <abs>/godot_fonts.gd
const FONTS := ["res://assets/fonts/LilitaOne-Regular.ttf", "res://assets/fonts/Nunito-Bold.woff2", "res://assets/fonts/Nunito-ExtraBold.woff2",
	"res://assets/fonts/Cinzel-Black.woff2", "res://assets/fonts/DejaVuSans.ttf", ""]
const SIZES := [9, 10, 11, 12, 13, 14, 15, 16, 18, 20, 21, 22, 24, 26, 28, 32, 36, 40, 48, 64]
const TEXTS := ["Hello World", "PLAY", "Fatebound", "1,234 gold", "Wavy AV To Ty", "The quick brown fox jumps over the lazy dog.", "x", "  spaced  ", "WWW iii", "100%"]
func _init() -> void:
	for fp in FONTS:
		var f: Font = ThemeDB.fallback_font if fp == "" else load(fp)
		for s in SIZES:
			var line := "F %s %d asc=%.4f desc=%.4f h=%.4f" % [fp.get_file() if fp != "" else "default", s, f.get_ascent(s), f.get_descent(s), f.get_height(s)]
			for t in TEXTS:
				line += " |%s|=%.4f" % [t, f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x]
			print(line)
	quit()
