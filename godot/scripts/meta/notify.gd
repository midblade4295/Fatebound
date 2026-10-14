extends RefCounted
# 0.31.119 (Kevin: "Do all" -- 5. "your chest is ready" notifications). The game's side of the FateboundNotify Android
# plugin (godot/android_plugins/fatebound_notify; only in the Play Store build -- the preview APK has no plugin, and then
# nothing here does anything).
#   - going to the background: one notification per chest that is unlocking, at the moment it's ready ("Your Silver
#     Chest is ready!"); coming back: they're all cancelled (you can see your chests then)
#   - Settings > NOTIFICATIONS > "Chest ready" (settings.notify, on by default)
#   - Android 13+ asks for permission: the first time a chest starts unlocking the game asks first in its own words
#     ("Want a notification when your chest is ready?") and only on YES shows Android's dialog (settings.notify_asked)
# Nothing leaves the phone: the notifications are scheduled on it.
# 0.31.131 (the iOS port, IOS_PORT_SPEC_FOR_CLAUDE.md §6): on iOS the same four calls come from FateboundNotifyIOS
# (godot/ios_plugins/fatebound_notify, UNUserNotificationCenter; a GDExtension in the iOS build only), so everything
# here -- the question, the toggle, the scheduling -- is the same on both phones.
const Eco = preload("res://scripts/meta/economy.gd")
const Platform = preload("res://scripts/meta/platform.gd")
const SINGLETON := "FateboundNotify"
const IOS_CLASS := "FateboundNotifyIOS"
const ID_BASE := 1000

var plugin = null                  # the Android singleton, the iOS extension's object, or a test's fake

func _init(fake = null) -> void:
	if fake != null:
		plugin = fake
	elif Engine.has_singleton(SINGLETON):
		plugin = Engine.get_singleton(SINGLETON)
	elif Platform.is_ios() and Platform.has_class(IOS_CLASS):
		plugin = ClassDB.instantiate(IOS_CLASS)

func available() -> bool:
	return plugin != null

static func enabled(profile) -> bool:
	return profile != null and bool(profile.d.settings.get("notify", true))

func has_permission() -> bool:
	return available() and bool(plugin.hasPermission())

func request_permission() -> void:
	if available():
		plugin.requestPermission()

func should_ask(profile) -> bool:
	# the game's own question, once: the first time a chest starts unlocking, when Android would need permission
	return available() and enabled(profile) and not has_permission() and not bool(profile.d.settings.get("notify_asked", false))

static func plan(profile) -> Array:
	# -> [{id, title, body, delay}] for every chest that is unlocking and not yet ready
	var out := []
	for c in profile.d.chests.slots:
		if int(c.start) < 0:
			continue
		var left: int = profile.chest_left(c)
		if left <= 0:
			continue
		var name := str(Eco.CHESTS[str(c.kind)].name)
		out.append({"id":ID_BASE + int(c.id), "title":"Your %s is ready!" % name,
			"body":"Open it in Fatebound for your rewards.", "delay":left})
	return out

func on_background(profile) -> int:
	# -> how many were scheduled
	if not available():
		return 0
	plugin.cancelAll()
	if not enabled(profile) or not has_permission():
		return 0
	var n := 0
	for it in plan(profile):
		plugin.schedule(int(it.id), str(it.title), str(it.body), int(it.delay))
		n += 1
	return n

func on_foreground() -> void:
	if available():
		plugin.cancelAll()
