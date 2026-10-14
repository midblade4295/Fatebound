extends Node
# 0.31.130 (the iOS port, IOS_PORT_SPEC_FOR_CLAUDE.md §3): App Store purchases, with the same face as billing.gd (Google
# Play) so the shop and the app don't care which store they talk to (scripts/meta/store_billing.gd picks one). The
# StoreKit 2 side is GodotApplePlugins' StoreKitManager (addons/GodotApplePluginsStoreKit, a GDExtension in the iOS build
# only; reached through ClassDB, so this script parses and stays inactive everywhere else).
#
# A purchase mirrors Play's exactly: Apple's sheet (the purchase carries appAccountToken = UUIDv5 of our account id,
# scripts/meta/apple_token.gd) -> the signed transaction (JWS) -> the Siege server checks it with Apple
# (server/iap_verify_apple.gd, message "iap" with "store":"apple") -> granted to the account once -> only THEN the
# transaction is finished. Anything not finished (no network, server not set up yet, app killed) comes back from
# StoreKit on the next start or resume (Transaction.unfinished), like Play's query_purchases. A gem pack's ledger token
# is "apple:<transactionId>", the starter pack's (bought once per Apple ID) "apple:<originalTransactionId>".
# RESTORE PURCHASES (the App Store requires one for the starter pack): AppStore.sync, then the current entitlements go
# through the same path (the server says whether this account already has it).
const Net = preload("res://scripts/siege/siege_net.gd")
const Platform = preload("res://scripts/meta/platform.gd")
const AppleToken = preload("res://scripts/meta/apple_token.gd")
const OPTION_CLASS := "StoreProductPurchaseOption"
const OK := 0                         # StoreKitManager.StoreKitStatus
const INVALID_PRODUCT := 1
const CANCELLED := 2                  # (StoreKit threw: no network, not allowed, ...)
const UNVERIFIED := 3
const USER_CANCELLED := 4
const PENDING := 5                    # Ask to Buy / Strong Customer Authentication: arrives later as an update
const VERIFY_TIMEOUT := 20.0
const TOKEN_PREFIX := "apple:"

signal changed                        # prices / readiness / busy changed: the shop redraws
signal granted(product: String, result: Dictionary)
signal note(text: String, good: bool)

var profile                           # Profile
var on_server_grant: Callable          # (granted dict with "profile") -- the app's EcoSync takes the account
var client = null                     # GodotApplePlugins' StoreKitManager, or a test double with the same calls and signals
var verify_fn: Callable               # (product, jws, token, cb(res)) -> void; default: ask the Siege server
var url := OS.get_environment("SIEGE_URL") if OS.has_environment("SIEGE_URL") else Net.DEFAULT_URL
var ready_ := false                   # Apple answered with the products
var prices := {}                      # product id -> "0,99 €" from Apple (the player's currency)
var products := {}                    # product id -> StoreProduct (the sheet needs it)
var busy := ""                        # the product whose sheet is open
var restoring := false                # RESTORE PURCHASES is running
var last_token := ""                  # the appAccountToken of the last purchase (tests)
var _restore_asked := false
var _checking := {}                   # ledger token -> true while the server is asked
var _reqs: Array = []                 # open verification sockets [{ws, sent, msg, cb, t0}]

static func supported() -> bool:
	return Platform.has_class(Platform.STOREKIT_CLASS)

func setup(p, c = null) -> void:
	profile = p
	if not verify_fn.is_valid():
		verify_fn = _verify_server
	client = c
	if client == null and supported():
		client = ClassDB.instantiate(Platform.STOREKIT_CLASS)
	if client == null:
		return
	client.products_request_completed.connect(_on_products)
	client.purchase_completed.connect(_on_purchase)
	client.transaction_updated.connect(_handle)
	client.unverified_transaction_updated.connect(_on_unverified)
	client.restore_completed.connect(_on_restored)
	client.current_entitlements_fetch_completed.connect(_on_entitlements)
	client.start()                        # listens for updates and hands back what wasn't finished
	_ask_products()

func active() -> bool:
	return client != null

func price(product: String) -> String:
	# Apple's price in the player's currency once known, else the US price from the table
	return str(prices.get(product, "$" + str((Net.IAP.get(product, {}) as Dictionary).get("usd", "?"))))

func can_buy(product: String) -> bool:
	if not ready_ or busy != "" or restoring or not Net.IAP.has(product) or not products.has(product):
		return false
	if bool((Net.IAP[product] as Dictionary).get("once", false)) and bool(profile.d.iap.starter):
		return false
	return true

func buy(product: String) -> void:
	if not active():
		note.emit("Gem packs are sold in the App Store version of Fatebound", false)
		return
	if not ready_:
		note.emit("The App Store isn't connected yet. Try again in a moment", false)
		_ask_products()
		return
	if not can_buy(product):
		return
	busy = product
	changed.emit()
	last_token = account_token()
	var opts := _options(last_token)
	if opts.is_empty():
		client.purchase(products[product])
	else:
		client.purchase_with_options(products[product], opts)

func restore() -> void:
	# RESTORE PURCHASES: Apple syncs (it may ask for the Apple ID password), then what this Apple ID owns is checked
	if not active() or restoring:
		return
	restoring = true
	_restore_asked = true
	changed.emit()
	client.restore_purchases()

func resume() -> void:
	# the app is opened again (or the server is reachable again): what StoreKit hasn't finished comes back
	if client == null:
		return
	if not ready_:
		_ask_products()
	client.fetch_unfinished_transactions()

func account_token() -> String:
	# the purchase is tied to the server account only when the phone uses one (billing.gd sends the account then too)
	if profile == null or not bool(profile.server_mode):
		return ""
	return AppleToken.for_account(str(profile.d.account.get("id", "")))

static func token_of(product: String, txn) -> String:
	# the ledger token (the server works out the same one from the verified transaction)
	var once := bool((Net.IAP.get(product, {}) as Dictionary).get("once", false))
	var n: Variant = txn.original_id if once else txn.transaction_id
	return TOKEN_PREFIX + str(int(n)) if int(n) > 0 else ""

# ---------------- Apple's answers ----------------
func _ask_products() -> void:
	client.request_products(PackedStringArray(Net.IAP.keys()))

func _on_products(list: Array, status: int) -> void:
	if status != OK:
		return
	for pr in list:
		if pr == null:
			continue
		var id := str(pr.product_id)
		if Net.IAP.has(id):
			products[id] = pr
			prices[id] = str(pr.display_price)
	ready_ = true
	changed.emit()

func _on_purchase(txn, status: int, _msg: String) -> void:
	busy = ""
	changed.emit()
	match status:
		OK:
			if txn != null:
				_handle(txn)
		USER_CANCELLED:
			pass
		PENDING:
			note.emit("Payment pending. Your gems arrive when Apple confirms it", true)
		UNVERIFIED:
			note.emit("The App Store couldn't confirm that purchase, so nothing was added", false)
		INVALID_PRODUCT:
			note.emit("That pack isn't on sale right now", false)
		_:
			note.emit("The purchase didn't go through. Try again in a moment", false)

func _on_unverified(txn, err: int) -> void:
	# StoreKit couldn't verify Apple's signature on this device: never granted (and never finished)
	print("billing_ios: unverified transaction %s (%d)" % [str(txn.product_id) if txn != null else "?", err])

func _handle(txn) -> void:
	if txn == null:
		return
	var product := str(txn.product_id)
	if not Net.IAP.has(product):
		return
	var token := token_of(product, txn)
	if token == "" or _checking.has(token):
		return
	if float(txn.revocation_date) > 0.0:
		txn.finish()                                    # refunded: nothing to deliver
		return
	if profile.iap_granted(token):
		if _restore_asked and bool(Net.IAP[product].get("once", false)):
			_restore_asked = false
			note.emit("Your Starter Pack is already on this account", true)
		txn.finish()
		return
	_checking[token] = true
	verify_fn.call(product, str(txn.jws_representation), token, func(v: Dictionary): _verified(product, token, txn, v))

func _verified(product: String, token: String, txn, v: Dictionary) -> void:
	_checking.erase(token)
	if v.get("granted", null) is Dictionary:
		# the server granted it to the account itself (or had already): take the account, then finish it
		var sg: Dictionary = v.granted
		if bool(sg.get("ok", false)):
			if not profile.iap_granted(token):
				profile.d.iap.done.append({"t":token, "p":product, "at":profile.now()})
			if bool(Net.IAP.get(product, {}).get("once", false)):
				profile.d.iap.starter = true
			if on_server_grant.is_valid():
				on_server_grant.call(sg)
			profile.save()
			granted.emit(product, sg)
			txn.finish()
			return
		if str(sg.get("why", "")) == "used":
			if _restore_asked and bool(Net.IAP[product].get("once", false)):
				_restore_asked = false
				note.emit("That Starter Pack belongs to another Fatebound account", false)
			txn.finish()                                # granted to an account before: nothing more to do
			return
	if bool(v.get("ok", false)):
		var g: Dictionary = profile.grant_iap(product, token)
		if bool(g.get("ok", false)):
			granted.emit(product, g)
			txn.finish()
		return
	match str(v.get("why", "")):
		"pending":
			note.emit("Payment pending. Your gems arrive when Apple confirms it", true)
		"bad":
			note.emit("Apple couldn't confirm that purchase, so nothing was added", false)
		"used":
			txn.finish()
		_:
			note.emit("Purchase received. It will be added as soon as the server can confirm it", true)

func _on_restored(status: int, _msg: String) -> void:
	if status != OK:
		restoring = false
		_restore_asked = false
		changed.emit()
		note.emit("Couldn't reach the App Store to restore purchases. Try again in a moment", false)
		return
	client.fetch_current_entitlements()               # each one comes through _handle, then the list

func _on_entitlements(list: Array) -> void:
	var ours := 0
	for e in list:
		if e != null and Net.IAP.has(str(e.product_id)):
			ours += 1
	if restoring and ours == 0:
		_restore_asked = false
		note.emit("Nothing to restore on this Apple ID. Gems stay with the Fatebound account that bought them", true)
	restoring = false
	changed.emit()

func _options(token: String) -> Array:
	# [appAccountToken] for purchase_with_options (a typed array of the plugin's option class), or [] without one
	if token == "" or not ClassDB.class_exists(OPTION_CLASS):
		return []
	var o: Variant = ClassDB.class_call_static(OPTION_CLASS, &"app_account_token", token)
	if o == null:
		return []
	var opts := Array([], TYPE_OBJECT, OPTION_CLASS, null)
	opts.append(o)
	return opts

# ---------------- the server's check ----------------
func _verify_server(product: String, jws: String, _token: String, cb: Callable) -> void:
	var ws := WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 21                       # (the answer can carry the account)
	if ws.connect_to_url(url) != OK:
		cb.call({"ok":false, "why":"unreachable"})
		return
	var msg := {"t":"iap", "v":Net.VERSION, "store":"apple", "product":product, "jws":jws, "pkg":Net.IAP_PACKAGE}
	if profile != null and bool(profile.server_mode):
		msg["acct"] = str(profile.d.account.id)             # the server grants it to this account
		msg["key"] = str(profile.d.account.key)
	_reqs.append({"ws":ws, "sent":false, "cb":cb, "t0":Time.get_ticks_msec() / 1000.0, "msg":msg})

func _process(_dt: float) -> void:
	for r in _reqs.duplicate():
		var ws: WebSocketPeer = r.ws
		ws.poll()
		var st := ws.get_ready_state()
		if st == WebSocketPeer.STATE_OPEN and not r.sent:
			ws.put_packet(Net.encode(r.msg))
			r.sent = true
		var answer := {}
		while ws.get_available_packet_count() > 0:
			var m := Net.decode(ws.get_packet())
			if str(m.get("t", "")) == "iap":
				answer = m
		var late: bool = Time.get_ticks_msec() / 1000.0 - float(r.t0) > VERIFY_TIMEOUT
		if not answer.is_empty() or st == WebSocketPeer.STATE_CLOSED or late:
			_reqs.erase(r)
			if st != WebSocketPeer.STATE_CLOSED:
				ws.close()
			(r.cb as Callable).call(answer if not answer.is_empty() else {"ok":false, "why":"unreachable"})
