extends Node
# 0.31.90: Google Play purchases (Kevin: "I want to incorporate IAP"). Only the Play app has the billing plugin
# (addons/GodotGooglePlayBilling, packed by the Gradle preset); everywhere else `supported()` is false and the shop
# says the packs are in the Play Store version.
#
# A purchase: Google's sheet -> on_purchase_updated -> the Siege server asks Google whether the token is real
# (server/iap_verify.gd, message "iap") -> the profile grants it once per token (Profile.grant_iap) -> a gem pack is
# consumed so it can be bought again; the starter pack is acknowledged (bought once). Anything not finished (no
# network, server not set up yet, app killed) is picked up again on the next start from Google's own list
# (query_purchases). Google refunds a purchase nobody acknowledges within 3 days, so nothing is acknowledged or
# consumed before it has been granted.
const Net = preload("res://scripts/siege/siege_net.gd")
const PLUGIN := "GodotGooglePlayBilling"
const PURCHASED := 1                  # BillingClient.PurchaseState
const PENDING := 2
const OK := 0                         # BillingClient.BillingResponseCode
const USER_CANCELED := 1
const ITEM_ALREADY_OWNED := 7
const VERIFY_TIMEOUT := 20.0

signal changed                        # prices / readiness / busy changed: the shop redraws
signal granted(product: String, result: Dictionary)
signal note(text: String, good: bool)

var profile                           # Profile
var client = null                     # the plugin's BillingClient, or a test double with the same calls and signals
var verify_fn: Callable               # (product, token, order, cb(res)) -> void; default: ask the Siege server
var url := OS.get_environment("SIEGE_URL") if OS.has_environment("SIEGE_URL") else Net.DEFAULT_URL
var ready_ := false
var prices := {}                      # product id -> "$0.99" from Google (local currency)
var busy := ""                        # the product whose sheet is open
var _checking := {}                   # token -> true while the server is asked
var _reqs: Array = []                 # open verification sockets [{ws, sent, msg, cb, t0}]

static func supported() -> bool:
	return Engine.has_singleton(PLUGIN)

func setup(p, c = null) -> void:
	profile = p
	if not verify_fn.is_valid():
		verify_fn = _verify_server
	client = c
	if client == null and supported():
		client = load("res://addons/GodotGooglePlayBilling/BillingClient.gd").new()
		add_child(client)
	if client == null:
		return
	client.connected.connect(_on_connected)
	client.disconnected.connect(func():
		ready_ = false
		changed.emit())
	client.connect_error.connect(func(_code, _msg):
		ready_ = false
		changed.emit())
	client.query_product_details_response.connect(_on_details)
	client.query_purchases_response.connect(_on_purchases)
	client.on_purchase_updated.connect(_on_updated)
	client.consume_purchase_response.connect(func(_r): pass)
	client.acknowledge_purchase_response.connect(func(_r): pass)
	client.start_connection()

func active() -> bool:
	return client != null

func price(product: String) -> String:
	# Google's price in the player's currency once known, else the US price from the table
	return str(prices.get(product, "$" + str((Net.IAP.get(product, {}) as Dictionary).get("usd", "?"))))

func can_buy(product: String) -> bool:
	if not ready_ or busy != "" or not Net.IAP.has(product):
		return false
	if bool((Net.IAP[product] as Dictionary).get("once", false)) and bool(profile.d.iap.starter):
		return false
	return true

func buy(product: String) -> void:
	if not active():
		note.emit("Gem packs are sold in the Google Play version of Fatebound", false)
		return
	if not ready_:
		note.emit("The Play Store isn't connected yet. Try again in a moment", false)
		client.start_connection()
		return
	if not can_buy(product):
		return
	busy = product
	changed.emit()
	var r: Dictionary = client.purchase(product)
	if int(r.get("response_code", OK)) != OK:
		busy = ""
		changed.emit()
		note.emit(_error_text(int(r.get("response_code", -99))), false)

func resume() -> void:
	# Ask Google for purchases not finished yet (the app is opened again, or the server is reachable again).
	if ready_ and client != null:
		client.query_purchases(0)

# ---------------- Google's answers ----------------
func _on_connected() -> void:
	ready_ = true
	client.query_product_details(PackedStringArray(Net.IAP.keys()), 0)
	client.query_purchases(0)
	changed.emit()

func _on_details(res: Dictionary) -> void:
	if int(res.get("response_code", -1)) != OK:
		return
	for pd in res.get("product_details", []):
		var offers: Variant = (pd as Dictionary).get("one_time_purchase_offer_details_list", null)
		if offers is Array and not (offers as Array).is_empty():
			prices[str(pd.product_id)] = str((offers[0] as Dictionary).get("formatted_price", ""))
	changed.emit()

func _on_purchases(res: Dictionary) -> void:
	if int(res.get("response_code", -1)) == OK:
		for pu in res.get("purchases", []):
			_handle(pu)

func _on_updated(res: Dictionary) -> void:
	var code := int(res.get("response_code", -1))
	busy = ""
	changed.emit()
	if code == OK:
		for pu in res.get("purchases", []):
			_handle(pu)
	elif code == ITEM_ALREADY_OWNED:
		resume()                                       # an earlier purchase never finished: finish it now
	elif code != USER_CANCELED:
		note.emit(_error_text(code), false)

func _handle(pu: Dictionary) -> void:
	var ids: Array = Array(pu.get("product_ids", []))
	var product := str(ids[0]) if not ids.is_empty() else ""
	var token := str(pu.get("purchase_token", ""))
	if not Net.IAP.has(product) or token == "" or _checking.has(token):
		return
	match int(pu.get("purchase_state", 0)):
		PENDING:
			note.emit("Payment pending. Your gems arrive when Google confirms it", true)
			return
		PURCHASED:
			pass
		_:
			return
	if profile.iap_granted(token):
		_finish(product, token, bool(pu.get("is_acknowledged", false)))
		return
	_checking[token] = true
	verify_fn.call(product, token, str(pu.get("order_id", "")), func(v: Dictionary): _verified(product, token, pu, v))

func _verified(product: String, token: String, pu: Dictionary, v: Dictionary) -> void:
	_checking.erase(token)
	if bool(v.get("ok", false)):
		var g: Dictionary = profile.grant_iap(product, token)
		if bool(g.get("ok", false)):
			granted.emit(product, g)
			_finish(product, token, bool(pu.get("is_acknowledged", false)))
		return
	match str(v.get("why", "")):
		"pending":
			note.emit("Payment pending. Your gems arrive when Google confirms it", true)
		"bad":
			note.emit("Google couldn't confirm that purchase, so nothing was added", false)
		"used":
			_finish(product, token, true)
		_:
			note.emit("Purchase received. It will be added as soon as the server can confirm it", true)

func _finish(product: String, token: String, acknowledged: bool) -> void:
	if bool((Net.IAP[product] as Dictionary).get("once", false)):
		if not acknowledged:
			client.acknowledge_purchase(token)
	else:
		client.consume_purchase(token)

static func _error_text(code: int) -> String:
	match code:
		2, 12, -1, -3:
			return "Couldn't reach Google Play. Check your connection"
		3:
			return "Google Play billing isn't available on this device"
		4:
			return "That pack isn't on sale right now"
		_:
			return "The purchase didn't go through (code %d)" % code

# ---------------- the server's check ----------------
func _verify_server(product: String, token: String, order: String, cb: Callable) -> void:
	var ws := WebSocketPeer.new()
	if ws.connect_to_url(url) != OK:
		cb.call({"ok":false, "why":"unreachable"})
		return
	_reqs.append({"ws":ws, "sent":false, "cb":cb, "t0":Time.get_ticks_msec() / 1000.0,
		"msg":{"t":"iap", "v":Net.VERSION, "product":product, "token":token, "order":order, "pkg":Net.IAP_PACKAGE}})

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
