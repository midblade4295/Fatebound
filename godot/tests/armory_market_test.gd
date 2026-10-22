extends SceneTree
# 0.31.204 (Kevin: "Now redo the locker menu. Change the name to armory and only put in there what the player owns.
# Also put a hero tab in the market that shows heroes that player doesn't own and that's where they will purchase
# them"; asked: the 5v5 picker "Send to Market", unearned titles "Hide them"):
#  1. the tab bar says ARMORY (the swords); the Armory: its painted hall, what you hold on it, HEROES / OUTFITS / TITLES
#     with their counts -- HEROES only yours (none locked, none with a price), MORE HEROES IN THE MARKET;
#  2. OUTFITS only yours (WEAR / WORN, no OWNED tag, nothing to buy), MORE IN THE MARKET; none: NO OUTFITS YET and the
#     way to the Market;
#  3. TITLES: NO TITLE and only the earned ones (EQUIP), how many are left to earn -- none of the locked ones;
#  4. a hero from the Armory: his window shows only his outfits you own, and N MORE OUTFITS IN THE MARKET (to its
#     OUTFITS); from the Market, all of them;
#  5. the Market's tabs: OUTFITS (the sale, SALE on it), HEROES (how many you don't own on it), GEMS; the gem pill opens
#     GEMS; HEROES: only the ones you don't own, by role, price in gold and gems, FREE / NEW, UNLOCK asks first (gold,
#     gems -- a shard and a Hero Token when you hold them), bought: gone from the Market, in the Armory; every hero
#     yours: EVERY HERO IS YOURS and the way to the Armory;
#  6. the 5v5 picker: a locked hero's GET IN MARKET and a free one's MARKET open the Market's HEROES with his card lit.
#   godot --headless --path godot -s res://tests/armory_market_test.gd
const App = preload("res://scripts/app/siege_app.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const Champions = preload("res://scripts/meta/champions.gd")
const ChampWindow = preload("res://scripts/app/champion_window.gd")
const HeroPanel = preload("res://scripts/app/moba_panel.gd")
var fails: Array = []
var app

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func btn(key: String, node: Node = null) -> Button:
	if node == null:
		node = app
	if node is Button and str(node.get_meta("action_key", "")) == key and node.is_visible_in_tree():
		return node
	for c in node.get_children():
		var r := btn(key, c)
		if r != null:
			return r
	return null

func press(key: String) -> bool:
	var b := btn(key)
	if b == null or b.disabled:
		check(false, "button %s present and enabled" % key)
		return false
	b.pressed.emit()
	return true

func texts(node: Node) -> Array:
	var out := []
	for l in node.find_children("*", "Label", true, false):
		if (l as Label).is_visible_in_tree():
			out.append((l as Label).text)
	for b in node.find_children("*", "Button", true, false):
		if (b as Button).is_visible_in_tree() and (b as Button).text != "":
			out.append((b as Button).text)
	return out

func has(node: Node, s: String) -> bool:
	return texts(node).any(func(t): return str(t).contains(s))

func keys(prefix: String) -> Array:
	var out := []
	for b in app.find_children("*", "Button", true, false):
		var k := str(b.get_meta("action_key", ""))
		if k.begins_with(prefix) and (b as Control).is_visible_in_tree():
			out.append(k.substr(prefix.length()))
	return out

func frames(n := 2) -> void:
	for i in n:
		await process_frame

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1/fatebound/siege/ws")   # nothing listens there
	app = App.new()
	var base := "user://armory-%d" % Time.get_ticks_usec()
	app.profile_path = base + "-profile.json"
	app.legacy_path = base + "-none.json"
	app.now_override = 1791000000
	root.add_child(app)
	await frames(3)
	var p = app.profile
	p.d.gold = 200000
	p.d.gems = 5000
	p.d.skins.append("knight_lion")
	p.wear_skin("knight", "knight_lion")
	p.d.skins.append("mage_frost")
	p.save()
	var mine: Array = Champions.ORDER.filter(func(h): return p.owns_hero(str(h)))
	var locked: Array = Champions.ORDER.filter(func(h): return not p.owns_hero(str(h)))

	# ---- 1. the Armory's HEROES
	check(app.tab_buttons["locker"].label.text == "ARMORY", "the tab bar says ARMORY")
	press("tab_locker")
	await frames()
	check(app.tab == "locker" and str(app.locker_tab) == "heroes" and has(app.content, "ARMORY")
		and has(app.content, "%d HEROES  ·  2 OUTFITS" % mine.size()), "the Armory: its hall, what you hold on it")
	check(btn("locker_tab_heroes") != null and btn("locker_tab_heroes").text == "HEROES %d" % mine.size()
		and btn("locker_tab_outfits").text == "OUTFITS 2" and btn("locker_tab_titles") != null, "HEROES / OUTFITS / TITLES with their counts")
	var cards := keys("champ_")
	check(cards.size() == mine.size() and locked.all(func(h): return not cards.has(str(h))), "only your heroes (%d), none of the %d locked" % [cards.size(), locked.size()])
	check(not has(app.content, "50,000") and not has(app.content, "FREE") and btn("champ_knight") != null
		and texts(btn("champ_knight")).has("LIONGUARD"), "no prices, no FREE; the Knight's card says the outfit he wears")
	check(btn("armory_to_heroes") != null and btn("armory_to_heroes").text.contains("%d MORE HERO" % locked.size()), "MORE HEROES IN THE MARKET")

	# ---- 2. OUTFITS
	press("locker_tab_outfits")
	await frames()
	var wear := keys("skin_wear_")
	check(wear.size() == 2 and wear.has("knight_lion") and wear.has("mage_frost") and keys("skin_buy_").is_empty()
		and not has(app.content, "OWNED"), "only your two outfits, WEAR / WORN, nothing to buy, no OWNED tag")
	check(btn("skin_wear_knight_lion").text == "WORN" and btn("skin_wear_mage_frost").text == "WEAR", "WORN on the Knight's, WEAR on the Mage's")
	press("skin_wear_mage_frost")
	await frames()
	check(p.worn_skin("mage") == "mage_frost" and btn("skin_wear_mage_frost").text == "WORN", "WEAR: the Mage wears it")
	check(btn("armory_to_outfits") != null and btn("armory_to_outfits").text.contains("%d MORE" % (Eco.SKINS.size() - 2)), "MORE IN THE MARKET")

	# ---- 3. TITLES
	p.d.owned.append("title_squire")
	press("locker_tab_titles")
	await frames()
	var eq := keys("equip_")
	check(eq.has("title_squire") and eq.has("default_title") and eq.size() == 2, "NO TITLE and only the earned one (%s)" % [eq])
	var left := 0
	for id in Eco.TITLE_GOALS:
		if not p.owns(id) and not Eco.retired(Eco.TITLE_GOALS[id]):
			left += 1
	left += Eco.PRIZE_TITLES.keys().filter(func(id): return not p.owns(id)).size()
	check(has(app.content, "%d more to earn by playing" % left) and not has(app.content, "LOCKED"), "how many are left (%d) -- none of them shown" % left)
	press("equip_title_squire")
	check(str(p.d.title) == "title_squire", "EQUIP")

	# ---- 4. a hero from the Armory: only his outfits you own
	press("locker_tab_heroes")
	await frames()
	press("champ_knight")
	await frames(3)
	var w = app.modal
	var tiles := keys("champ_skin_")
	check(w is ChampWindow and w.owned_only and tiles.size() == 2 and tiles.has("default") and tiles.has("knight_lion")
		and btn("champ_buy") == null, "his window from the Armory: his own look and the outfit you own, nothing to buy (%s)" % [tiles])
	check(btn("champ_more_market") != null and btn("champ_more_market").text.contains("%d MORE OUTFIT" % (Eco.skins_of("knight").size() - 1)),
		"N MORE OUTFITS IN THE MARKET")
	press("champ_more_market")
	await frames()
	check(not is_instance_valid(app.modal) and app.tab == "shop" and str(app.shop_tab) == "outfits" and btn("feat_open") != null, "... to the Market's OUTFITS")
	app.open_champion("knight")
	await frames(3)
	check(keys("champ_skin_").size() == 1 + Eco.skins_of("knight").size(), "from the Market: all his outfits")
	app.close_modal()

	# ---- 5. the Market's tabs and HEROES
	check(btn("shop_tab_outfits") != null and btn("shop_tab_heroes") != null and btn("shop_tab_gems") != null
		and texts(btn("shop_tab_outfits")).has("SALE") and texts(btn("shop_tab_heroes")).has(str(locked.size())), "OUTFITS (SALE) / HEROES (%d) / GEMS" % locked.size())
	press("tab_home")
	await frames()
	press("pill_gem")
	await frames()
	check(app.tab == "shop" and str(app.shop_tab) == "gems" and has(app.content, "GEM PACKS"), "the gem pill: the Market's GEMS")
	press("shop_tab_heroes")
	await frames()
	var forsale := keys("hero_look_")
	check(forsale.size() == locked.size() and forsale.all(func(h): return not p.owns_hero(str(h))), "HEROES: only the %d you don't own" % forsale.size())
	var hid := str(locked[0])
	var pr: Dictionary = p.hero_price(hid)
	var card: Node = btn("hero_look_" + hid).get_parent()
	check(has(card, Champions.short_of(hid).to_upper()) and has(card, str(int(pr.gems))) and btn("hero_unlock_" + hid) != null,
		"a card: %s, his price (gems %d)" % [Champions.short_of(hid), int(pr.gems)])
	press("hero_unlock_" + hid)
	await frames()
	check(app.modal != null and btn("hero_buy_gold") != null and btn("hero_buy_gems") != null and btn("hero_buy_shard") == null and btn("hero_buy_token") == null,
		"UNLOCK asks first: gold or gems")
	var gems0 := int(p.d.gems)
	press("hero_buy_gems")
	await frames()
	check(p.owns_hero(hid) and int(p.d.gems) == gems0 - int(pr.gems) and btn("hero_look_" + hid) == null, "bought for gems: gone from the Market")
	press("tab_locker")
	await frames()
	check(btn("champ_" + hid) != null, "... and in the Armory")
	# a shard and a Hero Token: their ways too
	var h2 := str(locked[1])
	p.d.shards.append(h2)
	p.d.tokens = 1
	app.open_market("heroes")
	await frames()
	press("hero_unlock_" + h2)
	await frames()
	check(btn("hero_buy_shard") != null and btn("hero_buy_token") != null, "holding a shard of him and a Hero Token: those ways too")
	press("hero_buy_token")
	await frames()
	check(p.owns_hero(h2) and int(p.d.tokens) == 0, "the Hero Token: he's yours")
	# every hero yours
	for h in locked:
		if not p.owns_hero(str(h)):
			p._own_hero(str(h))
	app.rebuild()
	await frames()
	check(keys("hero_look_").is_empty() and has(app.content, "EVERY HERO IS YOURS") and btn("market_to_armory") != null
		and not texts(btn("shop_tab_heroes")).any(func(t): return str(t).is_valid_int()), "every hero yours: EVERY HERO IS YOURS, the way to the Armory")
	press("market_to_armory")
	await frames()
	check(app.tab == "locker" and str(app.locker_tab) == "heroes" and btn("armory_to_heroes") == null, "OPEN THE ARMORY")

	# ---- 6. the 5v5 picker sends you to the Market
	var app2 = App.new()
	var base2 := "user://armory2-%d" % Time.get_ticks_usec()
	app2.profile_path = base2 + "-profile.json"
	app2.legacy_path = base2 + "-none.json"
	var wk := maxi(int(Time.get_unix_time_from_system()), Eco.SIX_LAUNCH + Eco.LAUNCH_DAYS * 86400)
	while Eco.free_heroes(wk).has("golem"):
		wk += 7 * 86400
	app2.now_override = wk
	app.queue_free()
	root.add_child(app2)
	app = app2
	await frames(3)
	app.open_moba()
	await frames()
	press("moba_hero_golem")
	check(app.modal is HeroPanel and app.modal._go.text == "GET IN MARKET" and not btn("moba_side_market"), "a locked hero: GET IN MARKET")
	press("moba_battle")
	await frames()
	var ring: Array = app.content.find_children("*", "Panel", true, false).filter(func(n): return n.has_meta("hero_focus_ring"))
	check(not is_instance_valid(app.modal) and app.tab == "shop" and str(app.shop_tab) == "heroes" and ring.size() == 1
		and ring[0].get_parent() == btn("hero_look_golem").get_parent(), "... the Market's HEROES, the Golem's card lit")
	var fr := str(Eco.free_heroes(app.profile.now())[0])
	app.open_moba()
	await frames()
	press("moba_hero_" + fr)
	check(app.modal._go.text == "BATTLE" and btn("moba_side_market") != null, "a free one: BATTLE, and MARKET beside it (%s)" % fr)
	press("moba_side_market")
	await frames()
	ring = app.content.find_children("*", "Panel", true, false).filter(func(n): return n.has_meta("hero_focus_ring"))
	check(app.tab == "shop" and str(app.shop_tab) == "heroes" and ring.size() == 1 and ring[0].get_parent() == btn("hero_look_" + fr).get_parent(),
		"MARKET: his card lit")
	print("ARMORY_MARKET_PASS" if fails.is_empty() else "ARMORY_MARKET_FAIL " + str(fails))
	quit(0 if fails.is_empty() else 1)
