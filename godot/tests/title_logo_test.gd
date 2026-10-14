extends SceneTree
# 0.31.113 (Kevin: "I like the all tied up one. Can you also make it so the king swings back and forth from the rope"):
#  - Home shows the "All Tied Up" title (scripts/app/title_logo.gd) in place of the text logo, its two layers loaded
#    and the sizes in title_logo.gd matching the art (tools/build_title_logo.py);
#  - the King swings both ways, no further than SWING_DEG, turning about the knot (that point never moves);
#  - at phone width the title sits between the side medallions, the swinging King included;
#  - with Reduce Motion on he hangs still.
#   godot --headless --path godot -s res://tests/title_logo_test.gd
const App = preload("res://scripts/app/siege_app.gd")
const TitleLogo = preload("res://scripts/app/title_logo.gd")
const UI2 = preload("res://scripts/app/ui2.gd")

var app
var still
var fails: Array = []
var t := 0.0
var lo := 0.0
var hi := 0.0
var knot0 := Vector2.ZERO
var knot_moved := 0.0

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _knot() -> Vector2:
	var k: Control = app.title_logo.king
	return k.get_global_transform() * k.pivot_offset

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")      # nothing listens there
	var base := "user://titlelogo-%d" % Time.get_ticks_usec()
	app = App.new()
	app.eco_autostart = false
	app.social_autostart = false
	app.version_check = false
	app.profile_path = base + "-profile.json"
	app.legacy_path = base + "-none.json"
	root.add_child(app)
	still = TitleLogo.new(true)
	root.add_child(still)
	still.size = Vector2(270, 270 * TitleLogo.aspect())

func _process(d: float) -> bool:
	t += d
	if t < 0.5:
		return false
	var tl = app.title_logo
	if knot0 == Vector2.ZERO:
		check(tl != null and tl.is_visible_in_tree() and app.tab == "home", "Home shows the title")
		check(tl.king != null, "the title's two layers load (logo_base, logo_king)")
		var bt: Texture2D = UI2.tex(UI2.V2 + "logo_base.webp")
		var kt: Texture2D = UI2.tex(UI2.V2 + "logo_king.webp")
		check(bt != null and Vector2(bt.get_size()) == TitleLogo.BASE, "logo_base.webp is %s" % str(TitleLogo.BASE))
		check(kt != null and Vector2(kt.get_size()) == TitleLogo.KING_SIZE, "logo_king.webp is %s" % str(TitleLogo.KING_SIZE))
		var has_text := false
		for l in app.hero_layer.find_children("*", "Label", true, false):
			if (l as Label).text == "FATEBOUND" or (l as Label).text.contains("CHANGE  FATE"):
				has_text = true
		check(not has_text, "the text logo and the old line are gone")
		var w: float = app.hero_layer.size.x
		check(absf(tl.position.x + tl.size.x * 0.5 - w * 0.5) < 1.0 and tl.size.x <= 300.0, "centred, at most 300 wide")
		# at phone width (420): the King's corners at full swing stay clear of the right-hand medallions (w - 62)
		var pw := 420.0
		var lw := minf(pw - 190.0, 226.0)                      # (0.31.138: smaller, in the war room's sky -- siege_app)
		var s := lw / TitleLogo.BASE.x
		var left := (pw - lw) * 0.5
		var piv := TitleLogo.PIVOT * s
		var far := 0.0
		for sg in [-1.0, 1.0]:
			var r: float = deg_to_rad(TitleLogo.SWING_DEG) * float(sg)
			for c in [Vector2.ZERO, Vector2(TitleLogo.KING_SIZE.x, 0), TitleLogo.KING_SIZE, Vector2(0, TitleLogo.KING_SIZE.y)]:
				var p: Vector2 = (TitleLogo.KING_AT + c) * s
				far = maxf(far, left + piv.x + (p - piv).rotated(r).x)
		check(left >= 62.0 and far < pw - 62.0, "at 420 wide the title (x %.0f) and the swinging King (to x %.0f) clear the medallions" % [left, far])
		knot0 = _knot()
		return false
	var r: float = rad_to_deg(tl.king.rotation)
	lo = minf(lo, r)
	hi = maxf(hi, r)
	knot_moved = maxf(knot_moved, _knot().distance_to(knot0))
	if t < 4.0:
		return false
	check(lo < -TitleLogo.SWING_DEG * 0.8 and hi > TitleLogo.SWING_DEG * 0.8, "the King swings both ways (%.1f to %.1f degrees)" % [lo, hi])
	check(lo >= -TitleLogo.SWING_DEG - 0.01 and hi <= TitleLogo.SWING_DEG + 0.01, "no further than %.0f degrees" % TitleLogo.SWING_DEG)
	check(knot_moved < 0.5, "he turns about the knot (it moved %.2f px)" % knot_moved)
	check(still.king != null and absf(still.king.rotation) < 0.0001, "with Reduce Motion he hangs still")
	print("TITLE_LOGO_PASS" if fails.is_empty() else "TITLE_LOGO_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
	return true
