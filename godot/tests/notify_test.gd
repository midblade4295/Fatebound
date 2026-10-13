extends SceneTree
# 0.31.119 (Kevin: "Do all" -- 5. "your chest is ready" notifications): scripts/meta/notify.gd with a fake of the
# FateboundNotify Android plugin, and the app around it.
#   - going to the background: one notification per unlocking chest, at the moment it's ready, with its name; nothing
#     without Android's permission or with the setting off; everything cancelled first and when the app comes back
#   - without the plugin (the preview APK): nothing at all, never asks
#   - the first UNLOCK asks in the game's own words; YES -> Android's dialog; asked once only
#   - Settings > NOTIFICATIONS: the "Chest ready" switch (greyed out without the plugin)
#   godot --headless --path godot -s res://tests/notify_test.gd
const Notify = preload("res://scripts/meta/notify.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const App = preload("res://scripts/app/siege_app.gd")

var fails: Array = []
var app
var fake
var frames := 0

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

class FakePlugin:
	var granted := false
	var requested := 0
	var scheduled := []
	var cancels := 0
	func hasPermission() -> bool:
		return granted
	func requestPermission() -> void:
		requested += 1
	func schedule(id: int, title: String, body: String, delay: int) -> void:
		scheduled.append({"id":id, "title":title, "body":body, "delay":delay})
	func cancelAll() -> void:
		cancels += 1
		scheduled.clear()

func _init() -> void:
	var p = Profile.new("user://notifytest-%d.json" % Time.get_ticks_usec(), "user://none.json")
	p.load_or_create()
	p.now_override = 1791806400
	p.add_chest("silver", {})
	p.add_chest("wooden", {})
	p.start_unlock(0)
	p.now_override += 600                                           # 10 minutes in
	var f := FakePlugin.new()
	var n = Notify.new(f)
	var plan: Array = Notify.plan(p)
	var left := int(Eco.CHESTS.silver.unlock) - 600
	check(plan.size() == 1 and int(plan[0].delay) == left and str(plan[0].title) == "Your Silver Chest is ready!" and int(plan[0].id) == 1000 + int(p.d.chests.slots[0].id),
		"the plan: the unlocking chest only, at the moment it's ready (%d s), by name" % left)
	check(n.on_background(p) == 0 and f.cancels == 1 and f.scheduled.is_empty(), "no permission: nothing scheduled (the old ones cancelled)")
	f.granted = true
	check(n.on_background(p) == 1 and f.scheduled.size() == 1 and int(f.scheduled[0].delay) == left, "with permission: one, in %d s" % left)
	n.on_foreground()
	check(f.scheduled.is_empty() and f.cancels == 3, "back in the game: cancelled")
	p.d.settings.notify = false
	check(n.on_background(p) == 0, "the setting off: nothing")
	p.d.settings.notify = true
	p.now_override += left + 5
	check(Notify.plan(p).is_empty(), "a chest that's already ready: no notification")
	var none = Notify.new()
	check(not none.available() and none.on_background(p) == 0 and not none.should_ask(p), "no plugin (the preview APK): nothing, and no question")
	f.granted = false
	check(n.should_ask(p), "the plugin, no permission, not asked yet: ask")
	# the app
	var base := "user://notifytest-app-%d" % Time.get_ticks_usec()
	var ap = Profile.new(base + "-profile.json", base + "-none.json")
	ap.load_or_create()
	ap.d.tutorial_done = true
	ap.add_chest("silver", {})
	ap.add_chest("wooden", {})
	ap.save()
	app = App.new()
	app.profile_path = base + "-profile.json"
	app.legacy_path = base + "-none.json"
	fake = FakePlugin.new()
	app.notify = Notify.new(fake)
	root.add_child(app)

func _find(node: Node, pred: Callable) -> Array:
	var out := []
	if pred.call(node):
		out.append(node)
	for c in node.get_children():
		out.append_array(_find(c, pred))
	return out

func _btn(key: String) -> Button:
	var l := _find(app, func(n): return n is Button and str(n.get_meta("action_key", "")) == key and (n as Control).is_visible_in_tree())
	return l[0] if not l.is_empty() else null

func _process(_d: float) -> bool:
	frames += 1
	if frames == 10:
		var ub := _btn("chest_unlock_0")
		check(ub != null, "Home: a chest to UNLOCK")
		if ub != null:
			ub.pressed.emit()
	elif frames == 14:
		check(app.modal != null and is_instance_valid(app.modal) and _find(app.modal, func(n): return n is Label and (n as Label).text == "CHEST NOTIFICATIONS").size() == 1,
			"the first UNLOCK asks: CHEST NOTIFICATIONS")
		_btn("modal_yes").pressed.emit()
		check(fake.requested == 1 and bool(app.profile.d.settings.notify_asked), "YES: Android's own dialog")
	elif frames == 18:
		check(not app.notify.should_ask(app.profile), "asked once only")
		fake.granted = true
		app._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
		check(fake.scheduled.size() == 1 and str(fake.scheduled[0].title) == "Your Silver Chest is ready!", "the app goes to the background: the chest's notification")
		app._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
		check(fake.scheduled.is_empty(), "...and back: cancelled")
		app.show_tab("settings")
	elif frames == 24:
		var t := _btn("notify")
		check(t != null and not t.disabled and t.button_pressed, "Settings: NOTIFICATIONS > Chest ready, on")
		app.notify = Notify.new()
		app.show_tab("settings")
	elif frames == 30:
		var t := _btn("notify")
		check(t != null and t.disabled, "without the plugin the switch is greyed out")
		print("NOTIFY_PASS" if fails.is_empty() else "NOTIFY_FAIL %s" % str(fails))
		quit(0 if fails.is_empty() else 1)
	return false
