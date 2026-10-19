extends SceneTree
# 0.31.130 the iOS port, step 1 (IOS_PORT_SPEC_FOR_CLAUDE.md §1, §3 client, §4 client): the game pretending to be an
# iPhone (Platform.forced = "ios") with doubles of GodotApplePlugins' StoreKit and Game Center, and pretending to be
# Android to show nothing changed there. REAL time.
#  1. Platform: Android answers what the old OS.get_name() checks gave; iOS the App Store; the desktop neither.
#  2. The facades pick billing.gd / play_games.gd on Android and the desktop, billing_ios.gd / game_center.gd on iOS.
#  3. The appAccountToken: UUIDv5 against Python's uuid5 (and RFC vectors).
#  4. billing_ios.gd against a StoreKit double: Apple's prices, buy -> server check -> grant -> THEN finish; the same
#     transaction again grants nothing; the starter pack's token is the original transaction's; pending / cancelled /
#     unreachable (granted on resume from StoreKit's unfinished list) / bad / refunded / granted by the server / used
#     elsewhere; RESTORE PURCHASES; the purchase carries the account's token; the server message.
#  5. game_center.gd against a Game Center double: signed in by itself, the alias, the link signal; achievements as
#     percentages with Apple's ids, only what changed; Apple's screen; declined -> where to sign in; resume.
#  6. The real app as an iPhone: the shop says App Store with Apple's prices and RESTORE PURCHASES, Settings shows
#     GAME CENTER; and as Android the shop says Google Play / PLAY STORE as before.
#   godot --headless --path godot -s res://tests/ios_port_test.gd
const Platform = preload("res://scripts/meta/platform.gd")
const StoreBilling = preload("res://scripts/meta/store_billing.gd")
const GameServices = preload("res://scripts/meta/game_services.gd")
const Billing = preload("res://scripts/meta/billing.gd")
const BillingIos = preload("res://scripts/meta/billing_ios.gd")
const PlayGames = preload("res://scripts/meta/play_games.gd")
const GameCenter = preload("res://scripts/meta/game_center.gd")
const AppleToken = preload("res://scripts/meta/apple_token.gd")
const Achievements = preload("res://scripts/meta/achievements.gd")
const GcIds = preload("res://scripts/meta/gc_achievement_ids.gd")
const UpdateScreen = preload("res://scripts/app/update_screen.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
const App = preload("res://scripts/app/siege_app.gd")
const Notify = preload("res://scripts/meta/notify.gd")
const Loader = preload("res://scripts/app/content_loader.gd")

var fails: Array = []
var frames := 0
var step := 0
var app
var fsk_app

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func fresh(tag: String):
	var p = Profile.new("user://ios_test_%s_%d.json" % [tag, Time.get_ticks_usec()], "user://none_%d.json" % Time.get_ticks_usec())
	p.load_or_create()
	return p

# ---------------- doubles of GodotApplePlugins ----------------
class FakeTxn extends RefCounted:
	var product_id := ""
	var transaction_id := 0
	var original_id := 0
	var revocation_date := 0.0
	var jws_representation := ""
	var finished := 0
	func _init(p: String, id: int, orig := 0, revoked := 0.0) -> void:
		product_id = p
		transaction_id = id
		original_id = orig if orig > 0 else id
		revocation_date = revoked
		jws_representation = "eyJ.%s.%d" % [p, id]
	func finish() -> void:
		finished += 1

class FakeProduct extends RefCounted:
	var product_id := ""
	var display_price := ""

class FakeStoreKit extends RefCounted:
	signal products_request_completed(products: Array, status: int)
	signal purchase_completed(transaction, status: int, message: String)
	signal transaction_updated(transaction)
	signal unverified_transaction_updated(transaction, verification_error: int)
	signal restore_completed(status: int, message: String)
	signal current_entitlements_fetch_completed(entitlements: Array)
	var calls: Array = []
	var catalog := {}                  # id -> Apple's price string (what App Store Connect has)
	var unfinished: Array = []         # transactions StoreKit hands back until finished
	var owned: Array = []              # current entitlements (non-consumables)
	func start() -> void:
		calls.append("start")
	func request_products(ids: PackedStringArray) -> void:
		calls.append("products %d" % ids.size())
		var out := []
		for id in ids:
			if catalog.has(id):
				var p := FakeProduct.new()
				p.product_id = id
				p.display_price = catalog[id]
				out.append(p)
		products_request_completed.emit(out, 0)
	func purchase(p) -> void:
		calls.append("buy " + str(p.product_id))
	func purchase_with_options(p, _opts) -> void:
		calls.append("buy+ " + str(p.product_id))
	func fetch_unfinished_transactions() -> void:
		calls.append("unfinished")
		for t in unfinished.duplicate():
			if t.finished == 0:
				transaction_updated.emit(t)
	func restore_purchases() -> void:
		calls.append("restore")
		restore_completed.emit(0, "")
	func fetch_current_entitlements() -> void:
		for t in owned:
			transaction_updated.emit(t)
		current_entitlements_fetch_completed.emit(owned.duplicate())

class FakeGC extends RefCounted:
	signal authenticated(ok: bool)
	signal failed(msg: String)
	var signed := true
	var asks := 0
	var reports: Array = []
	var shown := 0
	func authenticate() -> void:
		asks += 1
		if not signed:
			failed.emit("GKErrorDomain Code=2 cancelled")
		authenticated.emit(signed)
	func player_alias() -> String:
		return "Midblade"
	func team_player_id() -> String:
		return "T:1a2b3c4d"
	func report(list: Array, cb: Callable) -> void:
		reports.append_array(list)
		cb.call(null)
	func show_achievements() -> void:
		shown += 1
	func identity(cb: Callable) -> void:
		cb.call({"url":"https://static.gc.apple.com/public-key/gc-prod-10.cer", "data":PackedByteArray([1]), "salt":PackedByteArray([2]), "timestamp":1}, null)

const ALL_PRICES := {"gems_80":"0,99 €", "gems_500":"4,99 €", "gems_1100":"9,99 €", "gems_2400":"19,99 €", "gems_6500":"49,99 €",
	"gems_14000":"99,99 €", "starter_pack":"2,99 €"}

func _init() -> void:
	_platform()
	_facades()
	_token()
	_billing()
	_game_center()
	_notify()
	# ---- 6. the real app as an iPhone
	Platform.forced = "ios"
	var base := "user://ios_ui-%d" % Time.get_ticks_usec()
	app = App.new()
	app.profile_path = base + "-profile.json"
	app.legacy_path = base + "-none.json"
	app.now_override = 1791000000
	root.add_child(app)

func _platform() -> void:
	Platform.forced = "android"
	check(Platform.is_android() and not Platform.is_ios() and Platform.store() == "play" and Platform.store_name() == "Google Play"
		and Platform.store_short() == "Google Play" and Platform.store_button() == "PLAY STORE" and Platform.tracks_boot(),
		"Android: Google Play, PLAY STORE, BootGuard tracks")
	check(Platform.store_urls() == [UpdateScreen.MARKET_URL, UpdateScreen.WEB_URL] and UpdateScreen.MARKET_URL == "market://details?id=com.fatebound.game"
		and UpdateScreen.WEB_URL == "https://play.google.com/store/apps/details?id=com.fatebound.game", "Android: UPDATE tries the Play Store app, then its web page")
	var tried: Array = []
	UpdateScreen.open_store(func(_u): return FAILED, tried)
	var tried2: Array = []
	UpdateScreen.open_store(func(_u): return OK, tried2)
	check(tried == [UpdateScreen.MARKET_URL, UpdateScreen.WEB_URL] and tried2 == [UpdateScreen.MARKET_URL], "Android: the web page only when the Play Store app can't be opened")
	check(not Platform.has_iap() and not Platform.has_achievements() and not Platform.has_cloud_save(), "Android here: no Play plugins on the desktop, none claimed")
	Platform.forced = "ios"
	var tried3: Array = []
	UpdateScreen.open_store(func(_u): return OK, tried3)
	check(Platform.is_ios() and Platform.store() == "appstore" and Platform.store_name() == "the App Store" and Platform.store_button() == "APP STORE"
		and tried3 == [Platform.app_store_url()] and Platform.tracks_boot() and not Platform.has_cloud_save(), "iOS: the App Store, its page for UPDATE (%s), BootGuard tracks" % str(tried3))
	check(Platform.app_store_url() == "https://apps.apple.com/app/id6822556363",
		"the App Store page: apps.apple.com/app/id6822556363 (Fatebound Siege, 0.31.133)")
	check(not Platform.has_iap() and not Platform.has_achievements(), "iOS without GodotApplePlugins' classes (here): no store claimed")
	Platform.forced = ""
	var tried4: Array = []
	UpdateScreen.open_store(func(_u): return OK, tried4)
	check(Platform.os_name() == OS.get_name() and Platform.store() == "none" and not Platform.tracks_boot() and tried4 == [UpdateScreen.WEB_URL],
		"the desktop: neither store, Google Play's web page as before")

func _facades() -> void:
	for f in [["android", Billing, PlayGames], ["", Billing, PlayGames], ["ios", BillingIos, GameCenter]]:
		Platform.forced = f[0]
		var b: Node = StoreBilling.make()
		var g: Node = GameServices.make()
		check(b.get_script() == f[1] and g.get_script() == f[2], "%s: %s + %s" % [f[0] if f[0] != "" else "desktop",
			(f[1] as Script).resource_path.get_file(), (f[2] as Script).resource_path.get_file()])
		b.free()
		g.free()
	Platform.forced = ""
	# the same face: every call the app and the screens make exists on both
	var bi = BillingIos.new()
	var gc = GameCenter.new()
	var b0 = Billing.new()
	var g0 = PlayGames.new()
	var same := true
	for m in ["setup", "active", "price", "can_buy", "buy", "resume"]:
		same = same and bi.has_method(m) and b0.has_method(m)
	for m in ["setup", "active", "sign_in", "back_up_now", "choose", "pending_choice", "on_pause", "on_resume", "signed_in", "show_achievements", "last_backup"]:
		same = same and gc.has_method(m) and g0.has_method(m)
	for s in ["changed", "granted", "note"]:
		same = same and bi.has_signal(s) and b0.has_signal(s)
	for s in ["changed", "note", "ask", "restored"]:
		same = same and gc.has_signal(s) and g0.has_signal(s)
	for v in ["prices", "busy", "ready_", "on_server_grant", "verify_fn"]:
		same = same and v in bi and v in b0
	for v in ["state", "player", "why", "achievements"]:
		same = same and v in gc and v in g0
	check(same and bi.has_method("restore") and not b0.has_method("restore"), "the same face (calls, signals, fields); RESTORE PURCHASES only on the App Store")
	for n in [bi, gc, b0, g0]:
		n.free()

func _token() -> void:
	check(AppleToken.uuid5("6ba7b810-9dad-11d1-80b4-00c04fd430c8", "python.org") == "886313e1-3b8a-5372-9b90-0c9aee199e5d",
		"UUIDv5: the RFC/Python example (DNS, python.org)")
	check(AppleToken.uuid5("6ba7b810-9dad-11d1-80b4-00c04fd430c8", "account.fatebound.game") == AppleToken.NAMESPACE,
		"the namespace is uuid5(DNS, account.fatebound.game)")
	check(AppleToken.for_account("0123456789abcdef0123") == "ede02c0a-6538-592a-af28-99d1e03df7c8" and AppleToken.for_account("") == "",
		"an account's token = Python's uuid5(NAMESPACE, id); no account, no token")

func _billing() -> void:
	var bp = fresh("billing")
	var sk := FakeStoreKit.new()
	sk.catalog = ALL_PRICES.duplicate()
	sk.catalog.erase("gems_14000")                       # (not made in App Store Connect yet)
	var bill = BillingIos.new()
	root.add_child(bill)
	var verdicts := {}                                   # ledger token -> the server's answer
	var asked: Array = []                                # [product, jws, token]
	var net := {"down": false}
	bill.verify_fn = func(product, jws, token, cb):
		if net.down:
			cb.call({"ok":false, "why":"unreachable"})
			return
		asked.append([product, jws, token])
		cb.call(verdicts.get(token, {"ok":true}))
	var notes: Array = []
	bill.note.connect(func(t, good): notes.append([t, good]))
	var grants: Array = []
	bill.granted.connect(func(p, g): grants.append(p))
	check(not BillingIos.supported(), "no StoreKit class on the desktop: the real one is never made here")
	bill.setup(bp, sk)
	check(bill.active() and bill.ready_ and sk.calls.has("start") and sk.calls.has("products 7"), "started: StoreKit's listener, then the seven products asked for")
	check(bill.price("gems_80") == "0,99 €" and bill.price("gems_14000") == "$99.99" and not bill.prices.has("gems_14000")
		and not bill.can_buy("gems_14000") and bill.can_buy("gems_80"), "Apple's prices; a product Apple doesn't have isn't shown (prices) nor sold")
	# a purchase
	var g0 := int(bp.d.gems)
	bill.buy("gems_80")
	check(sk.calls.has("buy gems_80") and bill.busy == "gems_80" and not bill.can_buy("gems_500"), "buy opens Apple's sheet; one at a time")
	var t1 := FakeTxn.new("gems_80", 1001)
	sk.purchase_completed.emit(t1, BillingIos.OK, "")
	check(int(bp.d.gems) == g0 + 80 and t1.finished == 1 and bill.busy == "" and asked.size() == 1 and asked[0] == ["gems_80", t1.jws_representation, "apple:1001"],
		"Apple's signed transaction -> the server -> granted, THEN finished (token apple:1001)")
	sk.transaction_updated.emit(t1)
	check(int(bp.d.gems) == g0 + 80 and asked.size() == 1, "the same transaction again: nothing granted, the server not asked")
	# the starter pack: the original transaction's id
	var t2 := FakeTxn.new("starter_pack", 2002, 2000)
	sk.transaction_updated.emit(t2)
	check(bool(bp.d.iap.starter) and t2.finished == 1 and bp.iap_granted("apple:2000") and not bill.can_buy("starter_pack"),
		"the starter pack: token apple:<originalTransactionId>, finished, not for sale again")
	# pending (Ask to Buy) and cancelled
	bill.buy("gems_500")
	sk.purchase_completed.emit(null, BillingIos.PENDING, "Purchase pending")
	check(bill.busy == "" and notes.size() == 1 and str(notes[0][0]).begins_with("Payment pending"), "pending: frees the shop, says so")
	bill.buy("gems_500")
	sk.purchase_completed.emit(null, BillingIos.USER_CANCELLED, "User cancelled")
	check(bill.busy == "" and notes.size() == 1, "cancelled: frees the shop quietly")
	# the server can't be reached: not granted, not finished; StoreKit hands it back on resume
	var g1 := int(bp.d.gems)
	net.down = true
	var t3 := FakeTxn.new("gems_500", 3003)
	sk.unfinished.append(t3)
	sk.transaction_updated.emit(t3)
	check(int(bp.d.gems) == g1 and t3.finished == 0, "server unreachable: nothing granted, nothing finished")
	net.down = false
	bill.resume()
	check(int(bp.d.gems) == g1 + 500 and t3.finished == 1 and sk.calls.has("unfinished"), "on resume StoreKit's unfinished one is granted once, then finished")
	# bad, refunded, granted by the server, used by another account
	var t4 := FakeTxn.new("gems_6500", 4004)
	verdicts["apple:4004"] = {"ok":false, "why":"bad"}
	sk.transaction_updated.emit(t4)
	check(int(bp.d.gems) == g1 + 500 and t4.finished == 0, "a transaction Apple doesn't confirm: nothing granted, not finished")
	var n_asked := asked.size()
	var t5 := FakeTxn.new("gems_1100", 5005, 0, 1791000000.0)
	sk.transaction_updated.emit(t5)
	check(t5.finished == 1 and asked.size() == n_asked and int(bp.d.gems) == g1 + 500, "refunded (revocationDate): finished, never granted, not even asked")
	var adopted := []
	bill.on_server_grant = func(g): adopted.append(g)
	var t6 := FakeTxn.new("gems_2400", 6006)
	verdicts["apple:6006"] = {"ok":true, "granted":{"ok":true, "gems":2400, "profile":{"gems":1}}}
	sk.transaction_updated.emit(t6)
	check(adopted.size() == 1 and t6.finished == 1 and bp.iap_granted("apple:6006") and grants.has("gems_2400"),
		"granted by the server to the account: the account taken, recorded, finished")
	var t7 := FakeTxn.new("gems_80", 7007)
	verdicts["apple:7007"] = {"ok":true, "granted":{"ok":false, "why":"used"}}
	var g2 := int(bp.d.gems)
	sk.transaction_updated.emit(t7)
	check(t7.finished == 1 and int(bp.d.gems) == g2, "already granted to another account: finished, nothing here")
	# RESTORE PURCHASES
	sk.owned = [t2]
	var nn := notes.size()
	bill.restore()
	check(sk.calls.has("restore") and not bill.restoring and notes.size() == nn + 1 and str(notes[nn][0]).contains("already on this account"),
		"RESTORE PURCHASES: the starter pack this account has: says so %s" % str(notes.slice(nn)))
	sk.owned = []
	bill.restore()
	check(notes.size() == nn + 2 and str(notes[nn + 1][0]).begins_with("Nothing to restore"), "nothing owned: says so")
	var bq = fresh("restore")
	var sk2 := FakeStoreKit.new()
	sk2.catalog = ALL_PRICES.duplicate()
	var b2 = BillingIos.new()
	root.add_child(b2)
	b2.verify_fn = func(_p, _j, _t, cb): cb.call({"ok":true, "granted":{"ok":true, "gems":500, "gold":3000}})
	b2.setup(bq, sk2)
	var t8 := FakeTxn.new("starter_pack", 8008, 8000)
	sk2.owned = [t8]
	b2.restore()
	check(bool(bq.d.iap.starter) and t8.finished == 1 and bq.iap_granted("apple:8000"), "a new phone: RESTORE PURCHASES brings the starter pack back through the server")
	# the purchase carries the account's token; the server message
	bp.server_mode = true
	bp.d.account.id = "0123456789abcdef0123"
	bp.d.account.key = "k".repeat(32)
	bill.buy("gems_1100")
	check(bill.last_token == "ede02c0a-6538-592a-af28-99d1e03df7c8", "the purchase carries appAccountToken = UUIDv5(account)")
	sk.purchase_completed.emit(null, BillingIos.USER_CANCELLED, "")
	bill.url = "ws://127.0.0.1:1/fatebound/siege/ws"
	bill._verify_server("gems_80", "eyJ.x", "apple:1", func(_r): pass)
	var msg: Dictionary = bill._reqs[bill._reqs.size() - 1].msg if not bill._reqs.is_empty() else {}
	check(str(msg.get("t", "")) == "iap" and str(msg.get("store", "")) == "apple" and str(msg.get("jws", "")) == "eyJ.x" and int(msg.get("v", 0)) == Net.VERSION
		and str(msg.get("pkg", "")) == "com.fatebound.game" and str(msg.get("acct", "")) == "0123456789abcdef0123" and msg.has("key") and not msg.has("token"),
		"the server message: {t:iap, v, store:apple, product, jws, pkg, acct, key}")
	bill._reqs.clear()
	# no StoreKit at all
	var off = BillingIos.new()
	root.add_child(off)
	var off_notes := []
	off.note.connect(func(t, _g): off_notes.append(t))
	off.setup(fresh("off"))
	off.buy("gems_80")
	check(not off.active() and off_notes.size() == 1 and str(off_notes[0]).contains("App Store version"), "without StoreKit: inactive, says where packs are sold")

func _game_center() -> void:
	# the ids: Apple's own strings, one per achievement, within Apple's limits (<= 100 points each, <= 1000 in all)
	var keys_ok := GcIds.IDS.size() == Achievements.LIST.size()
	var pts := 0
	for a in Achievements.LIST:
		keys_ok = keys_ok and str(GcIds.IDS.get(a.key, "")) == "fatebound." + str(a.key) and int(a.xp) <= 100
		pts += int(a.xp)
	check(keys_ok and pts == 570, "18 Game Center ids fatebound.<key>, %d points (Apple: <= 1000, each <= 100)" % pts)
	var p = fresh("gc")
	p.d.tutorial_done = true
	p.d.stats.kills = 140
	p.d.stats.wins = 3
	p.d.stats["main_knight"] = 2
	p.d.stats["main_mage"] = 1
	var f := FakeGC.new()
	var gc = GameCenter.new()
	root.add_child(gc)
	var linked := []
	gc.signed.connect(func(t): linked.append(t))
	gc.setup(p, f)
	check(gc.active() and gc.signed_in() and gc.state == "synced" and gc.player == "Midblade" and linked == ["T:1a2b3c4d"],
		"signed in by itself at start: the alias, the account link asked for once (teamPlayerID)")
	var n := gc.sync_achievements()
	var got := {}
	for r in f.reports:
		got[r[0]] = float(r[1])
	check(is_equal_approx(got.get("fatebound.welcome", -1.0), 100.0) and is_equal_approx(got.get("fatebound.centurion", -1.0), 100.0)
		and is_equal_approx(got.get("fatebound.many_hats", -1.0), 200.0 / 7.0) and is_equal_approx(got.get("fatebound.slayer", -1.0), 14.0)
		and is_equal_approx(got.get("fatebound.siege_lord", -1.0), 6.0) and not got.has("fatebound.relentless") and not got.has("fatebound.fattening") and n == got.size(),
		"achievements as percent with Apple's ids (many_hats 2/7, slayer 140/1000, standard ones at 100 once met): %s" % str(got))
	check(gc.sync_achievements() == 0, "the same again: nothing reported")
	p.d.stats.wins = 4
	var n2 := gc.sync_achievements()
	check(n2 == 2 and f.reports.slice(n).map(func(r): return r[0]) == ["fatebound.siege_lord", "fatebound.legend"],
		"a win more: siege_lord and legend grow, first_victory isn't sent again %s" % str(f.reports.slice(n)))
	gc._ach_clock = GameCenter.ACH_EVERY
	gc._process(0.0)
	gc.show_achievements()
	check(f.shown == 1, "ACHIEVEMENTS: Apple's screen")
	var proof := {}
	gc.identity(func(d, e): proof.merge({"d":d, "e":e}))
	check(str(proof.get("d", {}).get("url", "")).begins_with("https://") and proof.get("e", 1) == null, "the identity signature for the server's account link")
	# declined: out, where to sign in, nothing sent; back from iOS Settings signed in
	var f2 := FakeGC.new()
	f2.signed = false
	var gc2 = GameCenter.new()
	root.add_child(gc2)
	gc2.setup(fresh("gc2"), f2)
	gc2.show_achievements()
	check(gc2.state == "out" and not gc2.signed_in() and f2.shown == 0 and gc2.why.contains("cancelled") and gc2.pending_choice().is_empty(),
		"declined: out (Apple's error kept for diagnostics), no screen")
	f2.signed = true
	gc2.on_resume()
	check(gc2.signed_in() and f2.asks == 2, "back from iOS Settings: asked again, signed in")
	var off = GameCenter.new()
	root.add_child(off)
	off.setup(fresh("gcoff"))
	check(not off.active() and off.state == "off", "without Game Center's classes: off")

func _notify() -> void:
	# chest-ready notifications: on iOS notify.gd takes FateboundNotifyIOS (ios_plugins/fatebound_notify), whose four
	# calls are named exactly like the Android plugin's, so the rest of notify.gd is the same code on both phones
	Platform.forced = "ios"
	var n = Notify.new()
	check(not n.available(), "iOS without the extension (here): no notifications claimed")
	Platform.forced = ""
	var reg := FileAccess.get_file_as_string("res://ios_plugins/fatebound_notify/src/register_types.cpp")
	var java := FileAccess.get_file_as_string("res://android_plugins/fatebound_notify/src/main/java/org/fatebound/notify/FateboundNotify.java")
	var same := reg.contains("GDREGISTER_CLASS(%s)" % Notify.IOS_CLASS)
	for m in ["hasPermission", "requestPermission", "schedule", "cancelAll"]:
		same = same and reg.contains("D_METHOD(\"%s\"" % m) and java.contains("public %s %s(" % ["boolean" if m == "hasPermission" else "void", m])
	check(same, "FateboundNotifyIOS registers the class notify.gd asks for, with the Android plugin's four calls")
	check(FileAccess.file_exists("res://ios_plugins/.gdignore") and FileAccess.file_exists("res://android_plugins/.gdignore"),
		"the native sources are hidden from Godot (.gdignore): never exported")
	# content packs: Library/Caches on iOS (never backed up to iCloud), user://packs elsewhere as before
	Platform.forced = "ios"
	var ios_dir := Loader.packs_dir()
	Platform.forced = "android"
	var and_dir := Loader.packs_dir()
	Platform.forced = ""
	check(and_dir == "user://packs" and ios_dir.ends_with("/fatebound_packs") and ios_dir.begins_with(OS.get_cache_dir()),
		"content packs: Caches on iOS (%s), user://packs on Android" % ios_dir)

# ---------------- 6. the screens ----------------
func _live(n: Node) -> bool:
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

func texts() -> String:
	var out := ""
	for l in app.content.find_children("*", "Label", true, false):
		if _live(l):
			out += (l as Label).text + "\n"
	return out

func _process(_d: float) -> bool:
	frames += 1
	if frames < 8:
		return false
	match step:
		0:
			check(app.billing.get_script() == BillingIos and app.play_games.get_script() == GameCenter, "the app on iOS: App Store purchases, Game Center")
			fsk_app = FakeStoreKit.new()
			fsk_app.catalog = ALL_PRICES.duplicate()
			app.billing.setup(app.profile, fsk_app)
			app.play_games.setup(app.profile, FakeGC.new())
			app.show_tab("shop")
		1:
			var b80 := btn("iap_gems_80")
			check(b80 != null and b80.text == "0,99 €" and not b80.disabled and btn("iap_gems_14000") != null and btn("iap_restore") != null
				and texts().contains("App Store  ·  gems never change damage"), "the shop on iOS: Apple's prices, the 99.99 pack once Apple has it, RESTORE PURCHASES")
			btn("iap_restore").pressed.emit()
			check(fsk_app.calls.has("restore"), "RESTORE PURCHASES asks Apple")
			app.show_tab("settings")
		2:
			check(texts().contains("GAME CENTER") and texts().contains("signed in as Midblade") and btn("gc_achievements") != null
				and btn("play_sign_in") == null and not texts().contains("GOOGLE PLAY"), "Settings on iOS: GAME CENTER, signed in, ACHIEVEMENTS")
			# 0.31.132: the ACCOUNT card, the same on both phones (no account on this desktop run: MOVE/DELETE greyed)
			check(texts().contains("ACCOUNT") and btn("move_new") != null and btn("move_enter") != null and btn("account_delete") != null
				and app.get("account_link") != null, "Settings: ACCOUNT -- MOVE TO ANOTHER PHONE, ENTER A CODE, DELETE ACCOUNT")
			app.play_games.state = "out"
			app.rebuild()
		3:
			check(texts().contains("iOS Settings > Game Center") and btn("gc_achievements") == null, "not signed in: where to sign in (no in-app sign-in, Apple's rule)")
			Platform.forced = "android"
			app.show_tab("shop")
		4:
			# the same app shell pretending to be Android (its billing is the iOS one made at start, so only the words
			# that come from Platform are looked at here; Android's own objects are checked in iap_test/play_games_test)
			app.billing = null
			app.rebuild()
		5:
			var b := btn("iap_gems_80")
			check(b != null and b.text == "PLAY STORE" and btn("iap_restore") == null and texts().contains("in the Google Play version"),
				"Android's shop words unchanged: PLAY STORE, in the Google Play version, no RESTORE")
			app.show_tab("settings")
		6:
			check(texts().contains("GOOGLE PLAY") and not texts().contains("GAME CENTER") and btn("move_enter") != null,
				"Android's Settings: GOOGLE PLAY as before, and the same ACCOUNT card")
			Platform.forced = ""
			print("IOS_PORT_PASS" if fails.is_empty() else "IOS_PORT_FAIL %s" % str(fails))
			quit(0 if fails.is_empty() else 1)
	step += 1
	return false
