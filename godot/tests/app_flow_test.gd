extends SceneTree
# The Siege app end to end through its real buttons (action_key metas), in REAL time.
# Shop buy (gold + gems with confirm), locker equip, pass claim + premium + claim all, challenge
# claim + reroll, rename, offline match -> rewards -> home, online failure -> home, back button.
const App = preload("res://scripts/app/siege_app.gd")
const Eco = preload("res://scripts/meta/economy.gd")

var app
var t := 0.0
var step := 0
var wait_until := 0.0
var fails := []
var gold_before := 0

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok: fails.append(what)

func btn(key: String, node: Node = null) -> Button:
	if node == null: node = app
	if node is Button and str(node.get_meta("action_key", "")) == key and node.is_visible_in_tree(): return node
	for c in node.get_children():
		var r := btn(key, c)
		if r != null: return r
	return null

func press(key: String) -> bool:
	var b := btn(key)
	if b == null or b.disabled:
		check(false, "button %s present and enabled" % key)
		return false
	b.pressed.emit()
	return true

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1/fatebound/siege/ws")   # nothing listens there
	var base := "user://appflow-%d" % Time.get_ticks_usec()
	app = App.new()
	app.profile_path = base + "-profile.json"
	app.legacy_path = base + "-none.json"
	app.now_override = 1791000000
	root.add_child(app)

func _process(d: float) -> bool:
	t += d
	if t < wait_until:
		return false
	var p = app.profile if app != null else null
	match step:
		0:
			check(app.tab == "home" and btn("play") != null, "app opens on Home with PLAY")
			p.d.gold = 50000; p.d.gems = 3000; p.save()
			press("tab_shop")
		1:
			var id: String = Eco.shop_daily(p.now())[0]
			var gold0: int = p.d.gold
			press("buy_" + id)
			check(p.owns(id) and int(p.d.gold) == gold0 - int(Eco.item_price(id).gold), "bought daily item %s for gold" % id)
			var gid: String = Eco.shop_featured(p.now())[0]
			press("buy_" + gid)
			check(app.modal != null and not p.owns(gid), "gem purchase asks for confirmation first")
			press("modal_yes")
			check(p.owns(gid), "gem item %s bought after confirming" % gid)
			var it := Eco.item(id)
			app.locker_class = "titles" if it.kind == "title" else str(it["class"])
			press("tab_locker")
			press("equip_" + id)
			var eq: bool = str(p.d.title) == id if it.kind == "title" else str(p.d.equip[it["class"]][it.kind]) == id
			check(eq, "equipped %s from the Locker" % id)
		2:
			p.d.pass.xp = 3 * Eco.TIER_XP + 10; p.save()
			press("tab_pass")
			press("claim_free_1")
			check(p.d.pass.free.has(1), "claimed free tier 1")
			press("buy_premium")
			press("modal_yes")
			check(bool(p.d.pass.premium) and int(p.d.gems) < 3000, "premium unlocked through the confirm dialog")
			press("claim_all")
			var all_done := true
			for tier in range(1, 4):
				for prem in [false, true]:
					if p.can_claim(tier, prem): all_done = false
			check(all_done, "claim all took every reached tier")
			check(str(app.tab_buttons["pass"].label.text) == "PASS", "PASS tab badge cleared")
		3:
			p.d.challenges.daily[0].progress = int(Eco.CHALLENGES[p.d.challenges.daily[0].id].goal); p.save()
			press("tab_home")
			var xp0: int = p.d.pass.xp
			press("claim_daily_0")
			check(bool(p.d.challenges.daily[0].claimed) and int(p.d.pass.xp) > xp0, "claimed a daily challenge from Home")
			var id1: String = p.d.challenges.daily[1].id
			press("reroll_1")
			check(p.d.challenges.daily[1].id != id1 and btn("reroll_2") == null, "one reroll, then reroll buttons disappear")
		4:
			press("tab_settings")
			var edit: LineEdit = null
			for n in app.find_children("*", "LineEdit", true, false): edit = n
			edit.text = "  Sir Kevin the Magnificent  "
			press("save_name")
			check(str(p.d.name) == "Sir Kevin the Ma", "name saved, trimmed, capped at 16 (%s)" % p.d.name)
			app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
			check(app.tab == "home", "back button returns to Home")
		5:
			gold_before = p.d.gold
			press("mode_bots")
			press("play")
			check(app.siege != null and not app.chrome.visible, "PLAY starts an offline match with the menu hidden")
			# The home hero owns a 4x-MSAA physical-resolution 3D viewport plus particles; it must not
			# keep rendering behind the match (the menu's looping PLAY tweens should pause too).
			check(not app.hero_layer.is_visible_in_tree() and app.hero_layer.process_mode == Node.PROCESS_MODE_DISABLED, "home hero (3D viewport + motes) is off during a match")
			check(app.chrome.process_mode == Node.PROCESS_MODE_DISABLED, "menu (and its looping PLAY tweens) paused during a match")
			wait_until = t + 1.5
		6:
			var s = app.siege.sim
			var me: Dictionary = s.by_id["you"]
			me.rescues = 1; me.kills = 5
			s.score = [3, 0]
			s._finish("rescue")
			wait_until = t + 1.0
		7:
			check(int(p.d.stats.matches) == 1 and int(p.d.gold) > gold_before, "match rewards landed in the profile (+%d gold)" % (int(p.d.gold) - gold_before))
			check(app.siege.hud.result_panel != null, "results panel shown")
			app.siege.hud.leave_requested.emit()
			wait_until = t + 0.5
		8:
			check(app.siege == null and app.chrome.visible and app.tab == "home", "HOME from results returns to the menu")
			check(app.hero_layer.is_visible_in_tree() and app.hero_layer.process_mode != Node.PROCESS_MODE_DISABLED and app.chrome.process_mode != Node.PROCESS_MODE_DISABLED, "hero and menu resume after the match")
			press("mode_online")
			press("play")
			check(app.siege != null and app.siege.online, "online PLAY starts an online session")
			wait_until = t + 5.0
		9:
			check(app.siege == null and app.chrome.visible, "unreachable server -> message, back to the menu")
			var reload = load("res://scripts/meta/profile.gd").new(p.path, p.legacy_path)
			reload.now_override = p.now_override
			reload.load_or_create()
			check(str(reload.d.name) == "Sir Kevin the Ma" and int(reload.d.stats.matches) == 1 and bool(reload.d.pass.premium), "everything persisted to disk")
			print("APP_FLOW_PASS" if fails.is_empty() else "APP_FLOW_FAIL %s" % str(fails))
			quit(0 if fails.is_empty() else 1)
			return false
	step += 1
	return false
