extends Control
# 0.31.214 (Kevin: "Show the starter pack on the front page and make sure it's eye-catching and has pretty graphics that
# doesn't look like AI made it"): the STARTER PACK window, from Home's offer card. Its picture big (the 3D render,
# tools/render_starter_pack.gd) in a warm card with light turning behind it, sparkles and a breathing glow; what's in it
# -- the gems, the gold and a Hero Token (any locked hero), each with its own icon; ONE-TIME OFFER; the price on a
# shining button (the store's purchase, as the Shop's: Screens._iap_button's rules -- live price, "PLAY STORE" /
# "APP STORE" where the store isn't there). It closes itself once the pack is bought.
const UI = preload("res://scripts/app/ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
const Platform = preload("res://scripts/meta/platform.gd")
const Screens = preload("res://scripts/app/screens.gd")

var app

func open(a) -> void:
	app = a
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.06, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			_close())
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var holder := MarginContainer.new()
	var cw := minf(372.0, app.size.x - 20.0)
	holder.custom_minimum_size = Vector2(cw, 0)
	center.add_child(holder)
	var v := UI2.frame(holder, "ember", 14, 22.0, "gold")
	v.add_theme_constant_override("separation", 10)
	# the head: the name, ✕
	var head := UI.row(v, 8)
	var tl := UI2.text(head, "STARTER PACK", 26, UI2.GOLD)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var x := UI2.button(head, "✕", "ghost", func(): _close(), "starter_close", 18, 40.0, 12.0)
	x.custom_minimum_size.x = 44
	# the picture
	var aw := cw - 40.0
	var ah := roundf(aw * 0.81)
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(aw, ah)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(stage)
	var well := Control.new()                      # (a dark well the light turns in)
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.clip_contents = true
	well.position = Vector2(0, 0)
	well.size = Vector2(aw, ah)
	stage.add_child(well)
	UI2.plate(well, "night", 18.0, "orange", {"fill_top": Color("#5a2208"), "fill_bottom": Color("#140602")})
	var ry := UI2.rays(well, aw * 1.5, Color(1.0, 0.82, 0.45), 26.0, 0.55)
	ry.position = Vector2(aw * 0.5, ah * 0.45) - ry.size * 0.5
	UI2.glow(well, Rect2(aw * 0.1, ah * 0.05, aw * 0.8, ah * 0.85), Color(1.0, 0.7, 0.3, 0.55))
	var art := TextureRect.new()
	art.texture = UI2.tex(Screens.STARTER_ART)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	art.position = Vector2(aw * 0.04, ah * 0.03)
	art.size = Vector2(aw * 0.92, ah * 0.94)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(art)
	UI2.bob(art, 4.0, 1.7)
	var tw_box := Control.new()
	tw_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tw_box.size = Vector2(aw, ah)
	stage.add_child(tw_box)
	Screens._twinkles(tw_box, 7, Color(1.0, 0.95, 0.78), Rect2(0.15, 0.2, 0.7, 0.6), 26.0)
	var once := UI2.chip(stage, "ONE-TIME OFFER", Color("#e8443a"), Color.WHITE, Color("#3a0805"))
	once.position = Vector2(10, 10)
	once.rotation = deg_to_rad(-6.0)
	# what's in it
	var sp: Dictionary = Net.IAP.starter_pack
	var items := HBoxContainer.new()
	items.add_theme_constant_override("separation", 8)
	items.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(items)
	# (the three in the picture's own light: tools/render_starter_pack.gd SHOT=gems | gold | token)
	_item(items, UI2.V2 + "offer/gems.webp", "%d" % int(sp.gems), "GEMS", Color("#8fd0ff"))
	_item(items, UI2.V2 + "offer/gold.webp", UI.grouped(int(sp.get("gold", 0))), "GOLD", UI2.GOLD)
	_item(items, UI2.V2 + "offer/token.webp", "HERO", "TOKEN", Color("#e2b8ff"))
	UI2.center(UI2.body(v, "A Hero Token unlocks any hero you don't have yet. Once per player.", 12, Color("#ffe9c7")))
	# the price
	var bl = app.billing
	var live: bool = bl != null and bl.active()
	var label := Platform.store_button()
	if live:
		label = "…" if str(bl.busy) == "starter_pack" else str(bl.price("starter_pack"))
	var b := UI2.button(v, label, "green" if live else "grey", func():
		app.sfx("tap")
		if bl != null:
			bl.buy("starter_pack")
		else:
			app.toast("Gem packs are sold in the %s version of Fatebound" % Platform.store_short(), UI.RED), "starter_buy", 22, 56.0, 16.0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if live:
		b.disabled = not bl.can_buy("starter_pack")
	UI2.sweep(b)

func _item(parent: Node, icon: String, big: String, small: String, col: Color) -> void:
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", 0)
	c.custom_minimum_size = Vector2(96, 0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	var box := Control.new()
	box.custom_minimum_size = Vector2(96, 88)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(box)
	UI2.plate(box, "night", 14.0, "gold", {"fill_top": Color("#3a1a0a"), "fill_bottom": Color("#150803")})
	var ic := UI2.img(box, icon, 50.0)
	ic.position = Vector2(23, 3)
	UI2.bob(ic, 2.0, 1.5, randf() * 0.8)
	var n := UI2.text(box, big, 18, Color.WHITE, UI2.INK, 4)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.position = Vector2(0, 50)
	n.size = Vector2(96, 20)
	var s := UI2.text(box, small, 11, col, UI2.INK, 3)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.position = Vector2(0, 68)
	s.size = Vector2(96, 14)

func _process(_d: float) -> void:
	if app != null and app.profile != null and bool(app.profile.d.iap.starter):
		app.close_modal()                          # (bought: the window goes, Home's card with it -- the app rebuilds)

func _close() -> void:
	app.sfx("menuClose")
	app.close_modal()
