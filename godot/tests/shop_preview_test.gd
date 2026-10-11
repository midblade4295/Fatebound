# The shop's tap-to-preview (0.31.96, Kevin: "make it so you can click the items in the store page and preview them").
# Real taps (a touch plus the mouse event Godot emulates from it, as on the phone) on every featured / daily / Arsenal
# card open its preview; then, through the preview's own buttons: the weapon view toggle, buying (gold; gems with the
# confirm, whose CANCEL goes back to the preview), equipping, an Arsenal's next weapon, closing.
extends SceneTree
const App = preload("res://scripts/app/siege_app.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const Screens = preload("res://scripts/app/screens.gd")
var app
var frames := 0
var targets: Array = []
var k := 0
var phase := 0
var pt := Vector2.ZERO
var fails: Array = []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok: fails.append(what)

func _init() -> void:
	var base := "user://shoppreview-%d" % Time.get_ticks_usec()
	app = App.new()
	app.profile_path = base + "-profile.json"
	app.legacy_path = base + "-none.json"
	app.now_override = 1791000000
	root.add_child(app)

func _touch(pos: Vector2, down: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0; ev.position = pos; ev.pressed = down
	root.push_input(ev, true)
	var mb := InputEventMouseButton.new()
	mb.device = InputEvent.DEVICE_ID_EMULATION
	mb.button_index = MOUSE_BUTTON_LEFT; mb.pressed = down; mb.position = pos; mb.global_position = pos
	mb.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	root.push_input(mb, true)

func _live(n: Node) -> bool:
	# a modal closed this frame is still in the tree until the frame ends (queue_free)
	while n != null:
		if n.is_queued_for_deletion():
			return false
		n = n.get_parent()
	return true

func btn(key: String) -> Button:
	for c in root.find_children("*", "Button", true, false):
		if str(c.get_meta("action_key", "")) == key and (c as Control).is_visible_in_tree() and _live(c):
			return c
	return null

func press(key: String) -> bool:
	var b := btn(key)
	if b == null or b.disabled:
		check(false, "button %s present and enabled" % key)
		return false
	b.pressed.emit()
	return true

func _process(_d: float) -> bool:
	frames += 1
	if frames == 5:
		app.profile.d.gold = 50000
		app.profile.d.gems = 3000
		app.show_tab("shop")
	if frames == 20:
		for b in root.find_children("*", "Button", true, false):
			var key := str(b.get_meta("action_key", ""))
			if key.begins_with("preview_"):
				targets.append(key)
		check(targets.size() >= 1 + 3 + Eco.PACKS.size(), "every shop card has a preview tap area (%d)" % targets.size())
	if frames > 20 and k < targets.size():
		var key: String = targets[k]
		match phase:
			0:
				# bring the card into view, then tap it above its middle (its price button is at the bottom)
				var r: Rect2 = btn(key).get_global_rect()
				var sc: ScrollContainer = app.content_scroll
				sc.scroll_vertical += int(r.get_center().y - sc.get_global_rect().get_center().y)
			1:
				var r: Rect2 = btn(key).get_global_rect()
				pt = r.position + Vector2(r.size.x * 0.5, r.size.y * 0.35)
				_touch(pt, true)
			2:
				_touch(pt, false)
			3:
				check(app.modal != null and btn("shop_preview_close") != null, "a tap on %s opens its preview" % key)
				press("shop_preview_close")
				check(app.modal == null, "the preview's ✕ closes it")
				k += 1
				phase = -1
		phase += 1
		return false
	if frames > 20 and k >= targets.size() and phase == 0:
		phase = 100
		var p = app.profile
		app.content_scroll.scroll_vertical = 0
		# a gold daily weapon: the toggle, buy, equip -- all inside the preview
		var did := ""
		for id in Eco.shop_daily(p.now()):
			if str(Eco.item(id).get("kind", "")) == "weapon" and Eco.item_price(id).has("gold") and not p.owns(id):
				did = id
				break
		check(did != "", "a gold daily weapon to preview")
		Screens.open_item(app, did)
		check(btn("shop_preview_hand") != null and btn("shop_preview_weapon") != null, "a weapon preview offers IN HAND and WEAPON")
		press("shop_preview_weapon")
		check(str(app.get_meta("shop_preview_mode", "")) == "weapon" and app.modal != null, "WEAPON shows the weapon on its own")
		var gold0: int = int(p.d.gold)
		press("shop_preview_buy")
		check(p.owns(did) and int(p.d.gold) == gold0 - int(Eco.item_price(did).gold), "bought %s from its preview" % did)
		check(app.modal != null and btn("shop_preview_equip") != null, "the preview stays open after buying, offering EQUIP")
		press("shop_preview_equip")
		var it := Eco.item(did)
		check(str(p.d.equip[it["class"]][it.kind]) == did and btn("shop_preview_equip").disabled, "equipped from the preview")
		press("shop_preview_hand")
		check(str(app.get_meta("shop_preview_mode", "")) == "hand", "IN HAND shows it on the hero again")
		press("shop_preview_close")
		# a gem item: the confirm's CANCEL goes back to the preview, BUY buys it
		var gid := ""
		for id in Eco.shop_featured(p.now()):
			if Eco.item_price(id).has("gems") and not p.owns(id):
				gid = id
				break
		if gid != "":
			Screens.open_item(app, gid)
			press("shop_preview_buy")
			check(btn("modal_yes") != null, "a gem buy asks first")
			press("modal_no")
			check(not p.owns(gid) and btn("shop_preview_buy") != null, "CANCEL goes back to the preview")
			press("shop_preview_buy")
			press("modal_yes")
			check(p.owns(gid) and btn("shop_preview_buy") == null and app.modal != null, "gem item %s bought, preview still open" % gid)
			press("shop_preview_close")
		# an Arsenal: its weapons one at a time, bought as a set
		var pid := ""
		for k2 in Eco.PACKS:
			if Eco.pack_price(k2, p.d.owned) > 0 and Eco.PACKS[k2].items.size() > 1:
				pid = k2
				break
		Screens.open_item(app, "", pid, 0)
		check(btn("shop_preview_item_1") != null and btn("shop_preview_buy_pack") != null, "an Arsenal preview lists its weapons")
		press("shop_preview_item_1")
		check(btn("shop_preview_buy_pack") != null, "the second weapon of %s shows" % pid)
		press("shop_preview_buy_pack")
		press("modal_yes")
		var all_owned := true
		for id in Eco.PACKS[pid].items:
			all_owned = all_owned and p.owns(id)
		check(all_owned and btn("shop_preview_owned") != null, "Arsenal %s bought from its preview" % pid)
		press("shop_preview_close")
		print("SHOP_PREVIEW_PASS" if fails.is_empty() else "SHOP_PREVIEW_FAIL %s" % str(fails))
		quit(0 if fails.is_empty() else 1)
	if frames > 3000:
		print("SHOP_PREVIEW_FAIL timeout")
		quit(1)
	return false
