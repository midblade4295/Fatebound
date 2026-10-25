extends SceneTree
# 0.31.214 (Kevin: "Show the starter pack on the front page ..."): the Starter Pack on Home, through the app's real
# buttons (no store here: the price button says the store's name).
#   - Home has the offer card (STARTER PACK, its picture, the buy button) while the pack isn't bought
#   - tapping the card opens the STARTER PACK window: the picture, the three things in it (Net.IAP's gems and gold, a
#     Hero Token), the buy button; ✕ closes it
#   - once the pack is bought (the profile's iap.starter): the window closes itself and Home has no card; the Shop's
#     starter card shows the same picture until then
#   godot --headless --path godot -s res://tests/starter_offer_test.gd
const App = preload("res://scripts/app/siege_app.gd")
const Screens = preload("res://scripts/app/screens.gd")
const StarterOffer = preload("res://scripts/app/starter_offer.gd")

var fails: Array = []
var app
var t := 0.0
var step := 0
var wait_until := 1.5

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func btn(key: String) -> BaseButton:
	for b in app.find_children("*", "BaseButton", true, false):
		if b.has_meta("action_key") and str(b.get_meta("action_key")) == key and (b as Control).is_visible_in_tree():
			return b
	return null

func texts(n: Node) -> String:
	var out := []
	for l in n.find_children("*", "Label", true, false):
		out.append(str((l as Label).text))
	for b in n.find_children("*", "Button", true, false):
		out.append(str((b as Button).text))
	return " | ".join(out)

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1/fatebound/siege/ws")   # nothing listens there
	var base := "user://starteroffer-%d" % Time.get_ticks_usec()
	app = App.new()
	app.eco_autostart = false
	app.social_autostart = false
	app.version_check = false
	app.profile_path = base + "-profile.json"
	app.legacy_path = base + "-none.json"
	app.now_override = 1791000000
	root.add_child(app)

func _process(d: float) -> bool:
	t += d
	if t < wait_until:
		return false
	wait_until = t + 0.4
	var p = app.profile
	match step:
		0:
			var tile: Node = app.find_child("StarterTile", true, false)
			check(app.tab == "home" and tile != null and not bool(p.d.iap.starter), "Home shows the Starter Pack card (not bought yet)")
			var art: TextureRect = tile.find_child("StarterArt", true, false) if tile != null else null
			check(art != null and art.texture != null and art.texture.get_width() >= 512, "its picture is the 3D render (%s)" % [str(art.texture.get_size()) if art != null and art.texture != null else "none"])
			check(tile != null and texts(tile).contains("STARTER PACK") and btn("iap_starter_pack") != null, "STARTER PACK on its ribbon, the buy button under it")
			var c := btn("home_starter")
			check(c != null, "the card is a button")
			if c != null:
				c.pressed.emit()
			step = 1
		1:
			var m = app.modal
			check(m is StarterOffer, "tapping it opens the STARTER PACK window")
			if m is StarterOffer:
				var s := texts(m)
				check(s.contains("STARTER PACK") and s.contains("500") and s.contains("3,000") and s.contains("HERO") and s.contains("TOKEN")
					and s.contains("ONE-TIME OFFER"), "the window: 500 gems, 3,000 gold, a Hero Token, ONE-TIME OFFER (%s)" % s.left(200))
				var pics: Array = (m as Node).find_children("*", "TextureRect", true, false).filter(func(x): return (x as TextureRect).texture != null \
					and str((x as TextureRect).texture.resource_path).contains("/offer/"))
				check(pics.size() >= 4, "the picture and the three things' own 3D icons (%d)" % pics.size())
				check(btn("starter_buy") != null, "its buy button")
				var x := btn("starter_close")
				if x != null:
					x.pressed.emit()
			step = 2
		2:
			check(not is_instance_valid(app.modal), "✕ closes it")
			app.shop_tab = "gems"                       # (the Shop's GEMS: the gem packs, the starter first)
			app.show_tab("shop")
			step = 3
		3:
			var sp := btn("iap_starter_pack")
			var found := false
			if sp != null:
				for x in (sp.get_parent() as Node).find_children("*", "TextureRect", true, false):
					if (x as TextureRect).texture != null and str((x as TextureRect).texture.resource_path) == Screens.STARTER_ART:
						found = true
			check(found, "the Shop's starter card shows the same picture")
			app.show_tab("home")
			step = 4
		4:
			btn("home_starter").pressed.emit()
			step = 5
		5:
			# bought (as the store's grant does): the window goes by itself, Home without the card
			p.d.iap.starter = true
			p.save()
			step = 6
		6:
			check(not is_instance_valid(app.modal), "bought: the window closes itself")
			app.rebuild()
			step = 7
		7:
			check(app.find_child("StarterTile", true, false) == null and btn("home_starter") == null, "bought: Home has no Starter Pack card")
			_finish()
	return false

func _finish() -> void:
	print("STARTER_OFFER_PASS" if fails.is_empty() else "STARTER_OFFER_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
