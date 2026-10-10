extends SceneTree
# 0.31.90 in-app purchases (Kevin: "I want to incorporate IAP"; Play Console side: PLAY_IAP_HANDOFF.md). REAL time.
#  1. The product table matches the handoff's IDs; Profile.grant_iap adds gems / Embers / a rare weapon once per token.
#  2. Billing (scripts/meta/billing.gd) against a stand-in for the Play plugin: prices from Google, buy -> server check ->
#     grant -> consume (gem packs) or acknowledge (starter pack); the same purchase seen again grants nothing; pending,
#     "unreachable" (kept, granted on resume) and "bad" purchases grant nothing.
#  3. server/iap_verify.gd against a fake Google (a tiny HTTP server here): the RS256 JWT verifies with the key's public
#     half, one access token serves two checks, and purchased / consumed / pending / unknown map to ok / used /
#     pending / bad.
#  4. The real server process: SIEGE_IAP_FAKE=1 answers ok over the WebSocket; with no key it answers "unconfigured".
const Net = preload("res://scripts/siege/siege_net.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const Billing = preload("res://scripts/meta/billing.gd")
const IapVerify = preload("res://server/iap_verify.gd")

var fails: Array = []
var phase := "start"
var t := 0.0
var wait_until := 0.0
var google: TCPServer = null
var google_port := 8093
var google_peers: Array = []
var google_log: Array = []              # [method path]
var google_state := {}                  # token -> {"purchaseState", "consumptionState"}
var google_pub: CryptoKey = null
var iap = null
var answers := {}
var pids: Array = []
var bill = null
var srv_answers := {}

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func fresh(tag: String):
	var p = Profile.new("user://iap_test_%s_%d.json" % [tag, Time.get_ticks_usec()], "user://none_%d.json" % Time.get_ticks_usec())
	p.load_or_create()
	return p

class FakeClient extends Node:
	signal connected
	signal disconnected
	signal connect_error(code, msg)
	signal query_product_details_response(r)
	signal query_purchases_response(r)
	signal on_purchase_updated(r)
	signal consume_purchase_response(r)
	signal acknowledge_purchase_response(r)
	var calls: Array = []
	var owned: Array = []                 # purchases Google still lists (not consumed)
	func start_connection(): calls.append("start"); connected.emit.call_deferred()
	func query_product_details(ids, _t): calls.append("details %d" % ids.size())
	func query_purchases(_t): calls.append("query"); query_purchases_response.emit({"response_code":0, "purchases":owned.duplicate()})
	func purchase(id: String) -> Dictionary: calls.append("buy " + id); return {"response_code":0}
	func consume_purchase(tok: String): calls.append("consume " + tok); owned = owned.filter(func(p): return p.purchase_token != tok)
	func acknowledge_purchase(tok: String): calls.append("ack " + tok)

static func purchase_dict(product: String, token: String, state := 1, acked := false) -> Dictionary:
	return {"product_ids":PackedStringArray([product]), "purchase_token":token, "purchase_state":state, "order_id":"GPA.1",
		"is_acknowledged":acked}

func _init() -> void:
	# ---- 1. the table and the profile
	var want := ["gems_80", "gems_500", "gems_1100", "gems_2400", "gems_6500", "starter_pack"]
	check(Net.IAP.keys() == want, "the six product IDs of PLAY_IAP_HANDOFF.md, in shop order %s" % str(Net.IAP.keys()))
	var doc := FileAccess.get_file_as_string("res://PLAY_IAP_HANDOFF.md")
	var all_in_doc := true
	for id in want:
		all_in_doc = all_in_doc and doc.contains("| `%s` |" % id)
	check(all_in_doc, "every product ID is in the handoff's product table")
	check(Net.IAP.gems_1100.gems >= Eco.PREMIUM_COST, "the 9.99 pack covers a Siege Pass (%d gems)" % Eco.PREMIUM_COST)
	var p = fresh("grant")
	var g0 := int(p.d.gems)
	var r: Dictionary = p.grant_iap("gems_500", "tok-aaaaaaaaaaaa")
	check(r.ok and int(r.gems) == 500 and int(p.d.gems) == g0 + 500, "a gem pack adds its gems")
	r = p.grant_iap("gems_500", "tok-aaaaaaaaaaaa")
	check(r.ok and bool(r.again) and int(p.d.gems) == g0 + 500, "the same token never grants twice")
	r = p.grant_iap("starter_pack", "tok-starter-123456")
	check(r.ok and int(p.d.embers) == 150 and str(r.item) != "" and p.owns(str(r.item)) and str(Eco.item(str(r.item)).rarity) == "rare"
		and bool(p.d.iap.starter), "the starter pack: 300 gems, 150 Embers and a rare weapon not owned yet (%s)" % str(r.item))
	check(not p.grant_iap("chest_royal", "tok-zzzzzzzzzzzz").ok, "an unknown product grants nothing")
	var p2 = fresh("allrares")
	for id in Eco.chest_pool("rare"):
		p2.d.owned.append(id)
	var g2 := int(p2.d.gems)
	r = p2.grant_iap("starter_pack", "tok-starter-999999")
	check(str(r.item) == "" and int(p2.d.gems) == g2 + 300 + Eco.DUPE_GOLD.rare / 10, "owning every rare: gems instead of the weapon")
	var p3 = Profile.new(p.path, "user://none.json")
	p3.load_or_create()
	check(p3.iap_granted("tok-aaaaaaaaaaaa") and int(p3.d.embers) == 150, "granted tokens and Embers are saved")

	# ---- 2. billing against a stand-in plugin
	var bp = fresh("billing")
	var fc := FakeClient.new()
	bill = Billing.new()
	root.add_child(bill)
	var verdicts := {}                                   # token -> the answer the fake server gives
	var asked: Array = []
	bill.verify_fn = func(product, token, _order, cb):
		asked.append(token)
		cb.call(verdicts.get(token, {"ok":true}))
	bill.setup(bp, fc)
	check(not Billing.supported(), "no Play plugin on the desktop: the real client is never made here")
	phase = "billing"

func _billing() -> void:
	var fc = bill.client
	var bp = bill.profile
	check(bill.ready_ and fc.calls.has("details 6") and fc.calls.has("query"), "connected: asks Google for the six prices and unfinished purchases")
	fc.query_product_details_response.emit({"response_code":0, "product_details":[
		{"product_id":"gems_80", "one_time_purchase_offer_details_list":[{"formatted_price":"1,09 €"}]}]})
	check(bill.price("gems_80") == "1,09 €" and bill.price("gems_500") == "$4.99", "Google's local price when known, else the US price")
	var g0 := int(bp.d.gems)
	bill.buy("gems_80")
	check(fc.calls.has("buy gems_80") and bill.busy == "gems_80" and not bill.can_buy("gems_500"), "buy opens Google's sheet; one at a time")
	fc.owned.append(purchase_dict("gems_80", "tok-buy-0000001"))
	fc.on_purchase_updated.emit({"response_code":0, "purchases":[purchase_dict("gems_80", "tok-buy-0000001")]})
	check(int(bp.d.gems) == g0 + 80 and fc.calls.has("consume tok-buy-0000001") and bill.busy == "", "checked, granted, then consumed")
	fc.on_purchase_updated.emit({"response_code":0, "purchases":[purchase_dict("gems_80", "tok-buy-0000001")]})
	check(int(bp.d.gems) == g0 + 80, "the same purchase reported again grants nothing")
	fc.on_purchase_updated.emit({"response_code":0, "purchases":[purchase_dict("starter_pack", "tok-starter-0000001")]})
	check(bool(bp.d.iap.starter) and fc.calls.has("ack tok-starter-0000001") and not fc.calls.has("consume tok-starter-0000001"),
		"the starter pack is acknowledged, never consumed")
	check(not bill.can_buy("starter_pack"), "and can't be bought again")
	var g1 := int(bp.d.gems)
	fc.on_purchase_updated.emit({"response_code":0, "purchases":[purchase_dict("gems_500", "tok-pend-0000001", 2)]})
	check(int(bp.d.gems) == g1 and not fc.calls.has("consume tok-pend-0000001"), "a pending payment grants nothing yet")
	# the server can't be reached: kept (not consumed, not granted), then granted on resume
	var vfn: Callable = bill.verify_fn
	var net := {"down": true}                            # (a lambda captures locals by value: a dictionary is shared)
	bill.verify_fn = func(product, token, order, cb):
		if net.down:
			cb.call({"ok":false, "why":"unreachable"})
		else:
			vfn.call(product, token, order, cb)
	fc.owned.append(purchase_dict("gems_500", "tok-later-000001"))
	fc.on_purchase_updated.emit({"response_code":0, "purchases":[purchase_dict("gems_500", "tok-later-000001")]})
	check(int(bp.d.gems) == g1 and not fc.calls.has("consume tok-later-000001"), "server unreachable: nothing granted, nothing consumed")
	net.down = false
	bill.resume()
	check(int(bp.d.gems) == g1 + 500 and fc.calls.has("consume tok-later-000001"), "picked up again on resume and granted once")
	bill.verify_fn = func(_p, _t, _o, cb): cb.call({"ok":false, "why":"bad"})
	fc.on_purchase_updated.emit({"response_code":0, "purchases":[purchase_dict("gems_6500", "tok-fake-0000001")]})
	check(int(bp.d.gems) == g1 + 500 and not fc.calls.has("consume tok-fake-0000001"), "a purchase Google doesn't know grants nothing")
	fc.on_purchase_updated.emit({"response_code":1, "purchases":[]})
	check(bill.busy == "", "a cancelled sheet frees the shop")

# ---------------- 3. a fake Google ----------------
func _google_start() -> void:
	google = TCPServer.new()
	check(google.listen(google_port, "127.0.0.1") == OK, "fake Google listening on %d" % google_port)
	var crypto := Crypto.new()
	var k := crypto.generate_rsa(2048)
	var pem := k.save_to_string()
	google_pub = CryptoKey.new()
	google_pub.load_from_string(k.save_to_string(true), true)
	var path := "user://iap_test_key.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"client_email":"fatebound-purchases@test.iam.gserviceaccount.com", "private_key":pem,
		"token_uri":"http://127.0.0.1:%d/token" % google_port}))
	f.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://iap_test_ledger.jsonl"))
	iap = IapVerify.new()
	iap.api_base = "http://127.0.0.1:%d" % google_port
	iap.ledger_path = "user://iap_test_ledger.jsonl"
	root.add_child(iap)
	check(iap.load_key(path) and iap.configured(), "the service-account key loads")
	# the JWT: three parts, RS256, verifies with the public half
	var jwt: String = IapVerify.make_jwt("a@b.c", pem, "http://x/token", 1791600000)
	var parts := jwt.split(".")
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	hc.update((parts[0] + "." + parts[1]).to_utf8_buffer())
	var sig := Marshalls.base64_to_raw(_unurl(parts[2]))
	check(parts.size() == 3 and crypto.verify(HashingContext.HASH_SHA256, hc.finish(), sig, google_pub), "the JWT is RS256 and verifies")
	var claims: Variant = JSON.parse_string(Marshalls.base64_to_utf8(_unurl(parts[1])))
	check(claims is Dictionary and claims.scope == IapVerify.SCOPE and claims.aud == "http://x/token" and int(claims.exp) - int(claims.iat) == 3600,
		"claims: the androidpublisher scope, the token URI, one hour")
	google_state = {"tok-g-ok-000001": {"purchaseState":0, "consumptionState":0, "orderId":"GPA.11", "purchaseType":0},
		"tok-g-used-00001": {"purchaseState":0, "consumptionState":1, "orderId":"GPA.12"},
		"tok-g-pend-00001": {"purchaseState":2, "consumptionState":0, "orderId":"GPA.13"},
		"tok-g-star-00001": {"purchaseState":0, "consumptionState":1, "orderId":"GPA.14"}}
	for tok in ["tok-g-ok-000001", "tok-g-used-00001", "tok-g-pend-00001", "tok-g-none-00001"]:
		var tk: String = tok
		iap.verify("gems_80", tk, func(res): answers[tk] = res)
	iap.verify("starter_pack", "tok-g-star-00001", func(res): answers["starter"] = res)

static func _unurl(s: String) -> String:
	var b := s.replace("-", "+").replace("_", "/")
	while b.length() % 4 != 0:
		b += "="
	return b

func _google_poll() -> void:
	while google.is_connection_available():
		google_peers.append({"c":google.take_connection(), "buf":PackedByteArray()})
	for gp in google_peers.duplicate():
		var c: StreamPeerTCP = gp.c
		c.poll()
		var n := c.get_available_bytes()
		if n > 0:
			var b: PackedByteArray = gp.buf
			b.append_array(c.get_data(n)[1])
			gp.buf = b
		var txt: String = (gp.buf as PackedByteArray).get_string_from_utf8()
		var head_end := txt.find("\r\n\r\n")
		if head_end < 0:
			continue
		var line := txt.get_slice("\r\n", 0)
		var length := 0
		for h in txt.substr(0, head_end).split("\r\n"):
			if h.to_lower().begins_with("content-length:"):
				length = int(h.split(":")[1].strip_edges())
		if txt.length() - head_end - 4 < length:
			continue
		var method := line.get_slice(" ", 0)
		var path := line.get_slice(" ", 1)
		google_log.append(method + " " + path)
		var code := 200
		var body := "{}"
		if path == "/token":
			body = JSON.stringify({"access_token":"ya29.test", "expires_in":3600})
		elif path.begins_with("/androidpublisher/v3/applications/%s/purchases/products/" % Net.IAP_PACKAGE):
			var tok := path.get_slice("/tokens/", 1).uri_decode()
			if not txt.contains("Authorization: Bearer ya29.test"):
				code = 401
			elif google_state.has(tok):
				body = JSON.stringify(google_state[tok])
			else:
				code = 404
		else:
			code = 404
		var resp := "HTTP/1.1 %d X\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [code, body.to_utf8_buffer().size(), body]
		c.put_data(resp.to_utf8_buffer())
		c.disconnect_from_host()
		google_peers.erase(gp)

func _google_checks() -> void:
	check(answers.has("tok-g-ok-000001") and answers["tok-g-ok-000001"].ok and bool(answers["tok-g-ok-000001"].test), "purchased: ok (a license tester's)")
	check(answers.has("tok-g-used-00001") and str(answers["tok-g-used-00001"].why) == "used", "a consumed gem pack: used")
	check(answers.has("tok-g-pend-00001") and str(answers["tok-g-pend-00001"].why) == "pending", "slow payment: pending")
	check(answers.has("tok-g-none-00001") and str(answers["tok-g-none-00001"].why) == "bad", "unknown token: bad")
	check(answers.has("starter") and answers["starter"].ok, "the starter pack: ok even though Google lists it consumed (bought once)")
	var tokens := google_log.filter(func(l): return str(l) == "POST /token").size()
	check(tokens == 1, "one access token for all five checks (%d requests)" % tokens)
	var led := FileAccess.get_file_as_string("user://iap_test_ledger.jsonl")
	check(led.split("\n", false).size() == 4 and not led.contains("tok-g-ok-000001"), "each decided check in the ledger, tokens only hashed (%d lines)" % led.split("\n", false).size())

# ---------------- 4. the real server ----------------
func _servers() -> void:
	for spec in [[8097, true], [8096, false]]:
		OS.set_environment("SIEGE_PORT", str(spec[0]))
		OS.set_environment("SIEGE_HOST", "127.0.0.1")
		OS.set_environment("SIEGE_IAP_KEY", "/nonexistent/key.json")
		if spec[1]:
			OS.set_environment("SIEGE_IAP_FAKE", "1")
		else:
			OS.unset_environment("SIEGE_IAP_FAKE")
		pids.append(OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://server/siege_server.gd"]))
	OS.unset_environment("SIEGE_IAP_FAKE")

func _ask_servers() -> void:
	var b2 = Billing.new()
	root.add_child(b2)
	b2.url = "ws://127.0.0.1:8097/fatebound/siege/ws"
	b2._verify_server("gems_80", "tok-srv-fake-0001", "GPA.9", func(res): srv_answers["fake"] = res)
	var b3 = Billing.new()
	root.add_child(b3)
	b3.url = "ws://127.0.0.1:8096/fatebound/siege/ws"
	b3._verify_server("gems_80", "tok-srv-none-0001", "GPA.9", func(res): srv_answers["none"] = res)

func _process(delta: float) -> bool:
	t += delta
	if google != null:
		_google_poll()
	match phase:
		"billing":
			if t > 0.3:
				_billing()
				_google_start()
				_servers()
				phase = "google"
				wait_until = t + 6.0
		"google":
			if answers.size() >= 5 or t > wait_until:
				_google_checks()
				phase = "servers"
				wait_until = t + 3.0
		"servers":
			if t > wait_until:
				_ask_servers()
				phase = "answers"
				wait_until = t + 25.0
		"answers":
			if srv_answers.size() >= 2 or t > wait_until:
				check(srv_answers.has("fake") and bool(srv_answers["fake"].get("ok", false)) and str(srv_answers["fake"].get("product", "")) == "gems_80",
					"server with SIEGE_IAP_FAKE=1: ok over the WebSocket %s" % str(srv_answers.get("fake", {})))
				check(srv_answers.has("none") and str(srv_answers["none"].get("why", "")) == "unconfigured",
					"server without a key: unconfigured %s" % str(srv_answers.get("none", {})))
				_finish()
				return true
	return false

func _finish() -> void:
	for pid in pids:
		OS.kill(pid)
		OS.execute("kill", ["-9", str(pid)])
	print("IAP_PASS" if fails.is_empty() else "IAP_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
