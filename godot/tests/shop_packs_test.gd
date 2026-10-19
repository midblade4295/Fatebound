extends SceneTree
# The shop's pack art and the bigger gold offers (0.31.106, Kevin: "Make new art for the higher tier packs so it shows
# more the higher the pack is. Add fun things to art for higher packs. Also maybe add some higher gold packs?"):
# five gem packs and five gold offers, each tier its own picture (assets/ui/packs), the gold offers giving more gold per
# gem as they grow, the biggest marked BEST VALUE, and the two new offers bought like the rest. 0.31.185 (Kevin: "I want
# the same IAP system as league of legends"): no gold offers any more -- League never sells its earned currency; the
# gem packs stay, each with its picture.
#   godot --headless --resolution 420x933 --path godot -s res://tests/shop_packs_test.gd
const App = preload("res://scripts/app/siege_app.gd")
const Eco = preload("res://scripts/meta/economy.gd")
var fails: Array = []
var app
var f := 0

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	var base := "user://shoppacks-%d" % Time.get_ticks_usec()
	app = App.new()
	app.profile_path = base + "-profile.json"
	app.legacy_path = base + "-none.json"
	app.now_override = 1791000000
	root.add_child(app)

func _arts() -> Array:
	var out := []
	for t in app.content.find_children("*", "TextureRect", true, false):
		var tr := t as TextureRect
		if tr.texture != null and tr.texture.resource_path.contains("/ui/packs/"):
			out.append(tr.texture.resource_path.get_file())
	return out

func _process(_d: float) -> bool:
	f += 1
	if f == 5:
		var missing := []
		for k in ["gem", "gold"]:
			for i in range(1, 6):
				if not ResourceLoader.exists("res://assets/ui/packs/%s_pack_%d.png" % [k, i]):
					missing.append("%s_pack_%d" % [k, i])
		check(missing.is_empty(), "ten pack pictures, gem and gold tiers 1-5 %s" % str(missing))
		check(not ("EXCHANGE" in Eco), "no gold offers (0.31.185)")
		app.profile.d.gems = 2000
		app.show_tab("shop")
	if f == 12:
		var arts := _arts()
		var want := ["gem_pack_1.png", "gem_pack_2.png", "gem_pack_3.png", "gem_pack_4.png", "gem_pack_5.png"]
		var lack := []
		for w in want:
			if not arts.has(w):
				lack.append(w)
		check(lack.is_empty(), "the shop shows every tier's picture %s" % str(lack))
		var keys := []
		for b in app.content.find_children("*", "BaseButton", true, false):
			var k := str(b.get_meta("action_key", ""))
			if k.begins_with("exchange_"):
				keys.append(k)
		check(keys.is_empty() and not app.profile.has_method("exchange"), "no gold offers in the shop, nothing trades gems for gold %s" % str(keys))
		print("SHOP_PACKS_PASS" if fails.is_empty() else "SHOP_PACKS_FAIL %s" % str(fails))
		quit(0 if fails.is_empty() else 1)
	return false
