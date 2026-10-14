extends RefCounted
# 0.31.130 (the iOS port, IOS_PORT_SPEC_FOR_CLAUDE.md §1): which phone and which store the game is on. Everything that
# differs between Android (Google Play) and iOS (the App Store) asks here instead of OS.get_name(), so on Android every
# answer is exactly what the old checks gave.
#   store()          "play" on Android, "appstore" on iOS, "none" elsewhere (desktop, tests)
#   store_url()      the game's page in that store (the update screen's UPDATE)
#   has_iap()        the store's purchase plugin is in this build
#   has_cloud_save() the store keeps a copy of the progress (Play Games; iOS v1 has none -- the server account)
#   has_achievements() the store's achievements service is in this build
# Tests pretend to be a platform with Platform.forced = "ios" (or "android"); "" is the real one.
const PACKAGE := "com.fatebound.game"                 # Play package and iOS bundle id (the same string)
const PLAY_MARKET_URL := "market://details?id=" + PACKAGE
const PLAY_WEB_URL := "https://play.google.com/store/apps/details?id=" + PACKAGE
# The App Store's numeric Apple ID of the app (App Store Connect > App Information): "Fatebound Siege" (0.31.133)
const APPLE_APP_ID := "6822556363"
const APP_STORE_SEARCH_URL := "https://apps.apple.com/us/search?term=Fatebound"

const PLAY_BILLING := "GodotGooglePlayBilling"        # Engine singletons of the Android plugins
const PLAY_GAMES := "GodotPlayGameServices"
const STOREKIT_CLASS := "StoreKitManager"             # GodotApplePlugins' classes (a GDExtension, in the iOS build only)
const GAMECENTER_CLASS := "GameCenterManager"

static var forced := ""                               # tests: "android" | "ios" | "" (the real platform)

static func os_name() -> String:
	match forced:
		"android":
			return "Android"
		"ios":
			return "iOS"
	return OS.get_name()

static func is_android() -> bool:
	return os_name() == "Android"

static func is_ios() -> bool:
	return os_name() == "iOS"

static func store() -> String:
	if is_android():
		return "play"
	if is_ios():
		return "appstore"
	return "none"

static func app_store_url() -> String:
	return "https://apps.apple.com/app/id" + APPLE_APP_ID if APPLE_APP_ID != "" else APP_STORE_SEARCH_URL

static func store_url() -> String:
	return app_store_url() if is_ios() else PLAY_WEB_URL

static func store_urls() -> Array:
	# what UPDATE tries, in order: the store app first, then its web page
	if is_ios():
		return [app_store_url()]
	if is_android():
		return [PLAY_MARKET_URL, PLAY_WEB_URL]
	return [PLAY_WEB_URL]

static func store_name() -> String:
	return "the App Store" if is_ios() else "Google Play"

static func store_short() -> String:
	# the shop's line ("Google Play  ·  gems never change damage", "in the Google Play version")
	return "App Store" if is_ios() else "Google Play"

static func store_button() -> String:
	# a gem pack's button where the store's plugin isn't in the build
	return "APP STORE" if is_ios() else "PLAY STORE"

static func has_class(cls: String) -> bool:
	return ClassDB.class_exists(cls) and ClassDB.can_instantiate(cls)

static func has_iap() -> bool:
	if is_ios():
		return has_class(STOREKIT_CLASS)
	return Engine.has_singleton(PLAY_BILLING)

static func has_cloud_save() -> bool:
	if is_ios():
		return false                                  # v1: the server account (transfer code / Game Center link)
	return Engine.has_singleton(PLAY_GAMES)

static func has_achievements() -> bool:
	if is_ios():
		return has_class(GAMECENTER_CLASS)
	return Engine.has_singleton(PLAY_GAMES)

static func plat() -> String:
	# 0.31.132: usage statistics' session_start "plat" (the reports split players by phone)
	if is_ios():
		return "ios"
	return "android" if is_android() else "desktop"

static func tracks_boot() -> bool:
	# BootGuard's crash tracking (a phone, not the desktop)
	return is_android() or is_ios()
