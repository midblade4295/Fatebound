extends SceneTree
# The shop's pack art and the bigger gold offers (0.31.106, Kevin: "Make new art for the higher tier packs so it shows
# more the higher the pack is. Add fun things to art for higher packs. Also maybe add some higher gold packs?"):
# five gem packs and five gold offers, each tier its own picture (assets/ui/packs), the gold offers giving more gold per
# gem as they grow, the biggest marked BEST VALUE, and the two new offers bought like the rest.
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
		var rates := []
		var rising := Eco.EXCHANGE.size() == 5
		for i in Eco.EXCHANGE.size():
			var r := float(Eco.EXCHANGE[i].gold) / float(Eco.EXCHANGE[i].gems)
			rates.append(snappedf(r, 0.1))
			if i > 0 and r <= float(Eco.EXCHANGE[i - 1].gold) / float(Eco.EXCHANGE[i - 1].gems):
				rising = false
		check(rising and int(Eco.EXCHANGE[4].gold) >= 30000, "five gold offers, more gold per gem as they grow %s" % str(rates))
		app.profile.d.gems = 2000
		app.show_tab("shop")
	if f == 12:
		var arts := _arts()
		var want := ["gem_pack_1.png", "gem_pack_2.png", "gem_pack_3.png", "gem_pack_4.png", "gem_pack_5.png",
			"gold_pack_1.png", "gold_pack_2.png", "gold_pack_3.png", "gold_pack_4.png", "gold_pack_5.png"]
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
		check(keys.has("exchange_gold_xl") and keys.has("exchange_gold_xxl") and keys.size() == 5, "five gold offers in the shop %s" % str(keys))
		var before := int(app.profile.d.gold)
		var r: Dictionary = app.profile.exchange("gold_xxl")
		check(r.ok and int(app.profile.d.gold) == before + 30000 and int(app.profile.d.gems) == 400, "the biggest offer: 1600 gems for 30,000 gold")
		print("SHOP_PACKS_PASS" if fails.is_empty() else "SHOP_PACKS_FAIL %s" % str(fails))
		quit(0 if fails.is_empty() else 1)
	return false
