extends SceneTree
# 0.31.131 the iOS port, step 4 (IOS_PORT_SPEC_FOR_CLAUDE.md §3 server, §9): App Store purchase checks. REAL time.
# A stand-in "Apple" (tools/apple_test_certs.py: a root, an intermediate and a leaf with Apple's marks, an API key) signs
# transactions like Apple's, and a fake App Store Server API (a tiny HTTP server here) answers for them.
#  1. server/iap_verify_apple.gd + server/apple_jws.py: a valid sandbox transaction is ok (ledger token, test); refused:
#     a wrong bundle, another product, a chain to another root, a tampered payload, refunded (Apple's API copy), bought
#     for another account (appAccountToken), unknown to Apple; a refused key -> unconfigured; no key -> unconfigured;
#     the starter pack's token is the original transaction's; SIEGE_IAP_FAKE accepts without checking; the API gets a
#     proper ES256 JWT (kid, issuer, aud, bundle); the ledger has the store and no whole token.
#  2. The real server process with that "Apple": two accounts made over the socket; billing_ios.gd's own message:
#     granted to the account once, the same transaction again "already yours", another account refused (token) or
#     "used" (a copy without the token), and the phone finishes only what was decided.
#   godot --headless --path godot -s res://tests/apple_iap_test.gd
const Net = preload("res://scripts/siege/siege_net.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const AppleToken = preload("res://scripts/meta/apple_token.gd")
const IapVerifyApple = preload("res://server/iap_verify_apple.gd")
const BillingIos = preload("res://scripts/meta/billing_ios.gd")

const SRV_PORT := 8113
const API_PORT := 8114
const ISSUER := "57246542-96fe-1a63-e053-0824d011072a"
const KEY_ID := "TESTKEY001"

var fails: Array = []
var phase := "unit"
var t := 0.0
var wait_until := 0.0
var dir := ""
var api: TCPServer = null
var api_peers: Array = []
var api_tx := {}                       # transactionId -> the API's JWS
var api_seen: Array = []               # [tx, jwt ok]
var answers := {}
var vers: Array = []
var pid := -1
var socks: Array = []                  # [{ws, msg, cb, sent}]
var accts := {}                        # "A"/"B" -> {id, key}
var e2e := {}
var a_id := ""

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

class Txn extends RefCounted:
	var product_id := ""
	var transaction_id := 0
	var original_id := 0
	var revocation_date := 0.0
	var jws_representation := ""
	var finished := 0
	func finish() -> void:
		finished += 1

func tool(args: Array) -> String:
	var out := []
	OS.execute("python3", [ProjectSettings.globalize_path("res://tools/apple_test_certs.py")] + args, out, true)
	return str(out[0]).strip_edges() if not out.is_empty() else ""

func tx(id: int, product: String, aat := "", extra := {}) -> Dictionary:
	var p := {"transactionId":str(id), "originalTransactionId":str(id), "bundleId":Net.IAP_PACKAGE, "productId":product,
		"signedDate":int(Time.get_unix_time_from_system()) * 1000, "environment":"Sandbox",
		"type":"Non-Consumable" if bool(Net.IAP.get(product, {}).get("once", false)) else "Consumable"}
	if aat != "":
		p["appAccountToken"] = aat
	p.merge(extra, true)
	return p

func sign_jws(p: Dictionary, other_root := false) -> String:
	# (the payload goes in a file: Godot's OS.execute doesn't keep the double quotes of an argument)
	var f := FileAccess.open(dir.path_join("payload.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(p))
	f.close()
	return tool(["sign", dir, "@" + dir.path_join("payload.json")] + (["--other-root"] if other_root else []))

func ver(key_id := KEY_ID, with_key := true) -> Node:
	OS.set_environment("SIEGE_APPLE_TEST_ROOT", dir.path_join("root.cer"))
	OS.set_environment("SIEGE_APPSTORE_API", "http://127.0.0.1:%d" % API_PORT)
	OS.set_environment("SIEGE_APPSTORE_ISSUER", ISSUER)
	OS.set_environment("SIEGE_APPSTORE_KEY_ID", key_id)
	if with_key:
		OS.set_environment("SIEGE_APPSTORE_KEY", dir.path_join("api.p8"))
	else:
		OS.unset_environment("SIEGE_APPSTORE_KEY")
	var v = IapVerifyApple.new()
	v.ledger_path = "user://apple_iap_test_ledger.jsonl"
	root.add_child(v)
	vers.append(v)
	return v

func _init() -> void:
	dir = ProjectSettings.globalize_path("user://apple_iap_test_%d" % Time.get_ticks_usec())
	check(tool(["make", dir]) == "TEST_APPLE_OK", "a stand-in Apple: root, intermediate, leaf, API key")
	api = TCPServer.new()
	check(api.listen(API_PORT, "127.0.0.1") == OK, "fake App Store Server API on %d" % API_PORT)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://apple_iap_test_ledger.jsonl"))
	var acct := "0123456789abcdef0123"
	var aat := AppleToken.for_account(acct)
	var cases := {
		"ok": [tx(2000000001, "gems_80", aat), "gems_80", acct, false],
		"bundle": [tx(2000000002, "gems_80", aat, {"bundleId":"com.example.other"}), "gems_80", acct, false],
		"product": [tx(2000000003, "gems_6500", aat), "gems_80", acct, false],
		"root": [tx(2000000004, "gems_80", aat), "gems_80", acct, true],
		"refunded": [tx(2000000005, "gems_500", aat), "gems_500", acct, false],
		"account": [tx(2000000006, "gems_80", AppleToken.for_account("ffffffffffffffffffff")), "gems_80", acct, false],
		"notfound": [tx(2000000007, "gems_80", aat), "gems_80", acct, false],
		"starter": [tx(2000000009, "starter_pack", aat, {"originalTransactionId":"2000000008"}), "starter_pack", acct, false],
		"noaat": [tx(2000000010, "gems_2400"), "gems_2400", acct, false],
	}
	var v = ver()
	check(v.configured() and v.describe().begins_with("Apple: TEST ROOT"), "the verifier: a test root, the key, the fake API (%s)" % v.describe())
	for k in cases:
		var c: Array = cases[k]
		var jws := sign_jws(c[0], c[3])
		if k != "notfound":
			var api_copy: Dictionary = (c[0] as Dictionary).duplicate()
			if k == "refunded":
				api_copy["revocationDate"] = int(Time.get_unix_time_from_system()) * 1000
				api_copy["revocationReason"] = 0
			api_tx[str(c[0].transactionId)] = sign_jws(api_copy, c[3])
		var key: String = k
		v.verify(str(c[1]), jws, str(c[2]), func(r): answers[key] = r)
	# tampered: a signed gem_80 with its payload changed to the biggest pack
	var good := sign_jws(tx(2000000011, "gems_80", aat))
	var parts := good.split(".")
	var pl: Dictionary = IapVerifyApple.unverified_payload(good)
	pl["productId"] = "gems_14000"
	parts[1] = Marshalls.utf8_to_base64(JSON.stringify(pl)).replace("+", "-").replace("/", "_").replace("=", "")
	v.verify("gems_14000", ".".join(parts), acct, func(r): answers["tampered"] = r)
	# a key Apple refuses; no key at all; SIEGE_IAP_FAKE
	var t12 := tx(2000000012, "gems_80", aat)
	api_tx["2000000012"] = sign_jws(t12)
	ver("WRONGKEY01").verify("gems_80", sign_jws(t12), acct, func(r): answers["denied"] = r)
	var nokey = ver(KEY_ID, false)
	check(not nokey.configured() and nokey.describe().begins_with("Apple: TEST ROOT"), "no key: not configured")
	nokey.verify("gems_80", sign_jws(t12), acct, func(r): answers["nokey"] = r)
	OS.set_environment("SIEGE_IAP_FAKE", "1")
	var fk = ver()
	OS.unset_environment("SIEGE_IAP_FAKE")
	fk.verify("gems_80", sign_jws(tx(2000000013, "gems_80", aat)), acct, func(r): answers["fake"] = r)
	v.verify("chest_royal", good, acct, func(r): answers["unknown"] = r)
	# ---- the real server, with this "Apple"
	var state := ProjectSettings.globalize_path("user://apple_iap_state_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(state)
	OS.set_environment("SIEGE_PORT", str(SRV_PORT))
	OS.set_environment("SIEGE_HOST", "127.0.0.1")
	OS.set_environment("STATE_DIRECTORY", state)
	OS.set_environment("SIEGE_APPSTORE_KEY_ID", KEY_ID)
	OS.set_environment("SIEGE_APPSTORE_KEY", dir.path_join("api.p8"))
	OS.set_environment("SIEGE_IAP_KEY", "/nonexistent/key.json")
	pid = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://server/siege_server.gd"])
	OS.unset_environment("STATE_DIRECTORY")
	wait_until = 30.0

# ---------------- the fake App Store Server API ----------------
func _api_poll() -> void:
	while api.is_connection_available():
		api_peers.append({"c":api.take_connection(), "buf":PackedByteArray()})
	for ap in api_peers.duplicate():
		var c: StreamPeerTCP = ap.c
		c.poll()
		var n := c.get_available_bytes()
		if n > 0:
			var b: PackedByteArray = ap.buf
			b.append_array(c.get_data(n)[1])
			ap.buf = b
		var txt: String = (ap.buf as PackedByteArray).get_string_from_utf8()
		if not txt.contains("\r\n\r\n"):
			continue
		var line := txt.get_slice("\r\n", 0)
		var path := line.get_slice(" ", 1)
		var jwt := ""
		for h in txt.split("\r\n"):
			if h.to_lower().begins_with("authorization: bearer "):
				jwt = h.substr(22).strip_edges()
		var code := 404
		var body := "{}"
		var id := path.get_file()
		var jwt_ok := jwt != "" and _jwt_ok(jwt)
		api_seen.append([id, jwt_ok])
		if not path.begins_with("/inApps/v1/transactions/"):
			code = 404
		elif not jwt_ok:
			code = 401
		elif api_tx.has(id):
			code = 200
			body = JSON.stringify({"signedTransactionInfo":api_tx[id]})
		var resp := "HTTP/1.1 %d X\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [code, body.to_utf8_buffer().size(), body]
		c.put_data(resp.to_utf8_buffer())
		c.disconnect_from_host()
		api_peers.erase(ap)

func _jwt_ok(jwt: String) -> bool:
	# Apple's own check, as far as a test can: ES256 by the key, and the claims an In-App Purchase key's JWT must have
	var parts := jwt.split(".")
	if parts.size() != 3:
		return false
	var h: Dictionary = IapVerifyApple.unverified_payload("x." + parts[0] + ".x")
	var c: Dictionary = IapVerifyApple.unverified_payload(jwt)
	if str(h.get("alg", "")) != "ES256" or str(h.get("kid", "")) != KEY_ID or str(c.get("iss", "")) != ISSUER \
			or str(c.get("aud", "")) != "appstoreconnect-v1" or str(c.get("bid", "")) != Net.IAP_PACKAGE \
			or int(c.get("exp", 0)) - int(c.get("iat", 0)) > 3600:
		return false
	var out := []
	return OS.execute("python3", [ProjectSettings.globalize_path("res://tools/apple_test_certs.py"), "verify-jwt", dir, jwt], out) == 0

# ---------------- checks ----------------
func _unit_checks() -> void:
	var ok: Dictionary = answers.get("ok", {})
	check(bool(ok.get("ok", false)) and str(ok.get("token", "")) == "apple:2000000001" and bool(ok.get("test", false)),
		"a valid sandbox purchase: ok, token apple:<transactionId>, test %s" % str(ok))
	for k in ["bundle", "product", "root", "tampered", "refunded", "account", "notfound", "unknown"]:
		check(str(answers.get(k, {}).get("why", "")) == "bad" and not bool(answers.get(k, {}).get("ok", true)), "refused: %s %s" % [k, str(answers.get(k, {}))])
	check(str(answers.get("denied", {}).get("why", "")) == "unconfigured", "Apple refuses the key: unconfigured, nothing decided %s" % str(answers.get("denied", {})))
	check(str(answers.get("nokey", {}).get("why", "")) == "unconfigured", "no key: unconfigured")
	check(bool(answers.get("starter", {}).get("ok", false)) and str(answers.starter.get("token", "")) == "apple:2000000008",
		"the starter pack: token apple:<originalTransactionId> %s" % str(answers.get("starter", {})))
	check(bool(answers.get("noaat", {}).get("ok", false)), "no appAccountToken (bought without an account): ok, the ledger still guards it")
	check(bool(answers.get("fake", {}).get("ok", false)) and bool(answers.fake.get("test", false)), "SIEGE_IAP_FAKE: accepted without checking")
	var jwt_good := api_seen.filter(func(s): return bool(s[1])).size()
	var jwt_bad := api_seen.filter(func(s): return not bool(s[1])).size()
	check(jwt_good >= 8 and jwt_bad == 1, "Apple's API asked with a proper ES256 JWT (%d), the refused key once (%d)" % [jwt_good, jwt_bad])
	check(not api_seen.any(func(s): return str(s[0]) in ["2000000004", "2000000011"]),
		"a forged chain or a tampered payload never reaches Apple's API (refused first)")
	var led := FileAccess.get_file_as_string("user://apple_iap_test_ledger.jsonl")
	check(led.contains("\"store\":\"apple\"") and led.contains("\"v\":\"ok\"") and led.contains("bad refunded") and led.contains("bad account")
		and not led.contains("apple:2000000001"), "the ledger: store apple, verdicts, tokens hashed")

# ---------------- the socket ----------------
func ask(msg: Dictionary, cb: Callable) -> void:
	var ws := WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 21
	ws.connect_to_url("ws://127.0.0.1:%d/fatebound/siege/ws" % SRV_PORT)
	socks.append({"ws":ws, "msg":msg, "cb":cb, "sent":false})

func _socks_poll() -> void:
	for s in socks.duplicate():
		var ws: WebSocketPeer = s.ws
		ws.poll()
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN and not s.sent:
			ws.put_packet(Net.encode(s.msg))
			s.sent = true
		while ws.get_available_packet_count() > 0:
			var m := Net.decode(ws.get_packet())
			if str(m.get("t", "")) == str(s.msg.t):
				socks.erase(s)
				(s.cb as Callable).call(m)
				return
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			socks.erase(s)
			(s.cb as Callable).call({})

func phone(who: String):
	var p = Profile.new("user://apple_e2e_%s_%d.json" % [who, Time.get_ticks_usec()], "user://none.json")
	p.load_or_create()
	p.server_mode = true
	p.d.account = {"id":str(accts[who].id), "key":str(accts[who].key)}
	var b = BillingIos.new()
	b.url = "ws://127.0.0.1:%d/fatebound/siege/ws" % SRV_PORT
	root.add_child(b)
	b.profile = p
	b.verify_fn = b._verify_server
	return b

func txn(p: Dictionary) -> Txn:
	var x := Txn.new()
	x.product_id = str(p.productId)
	x.transaction_id = int(p.transactionId)
	x.original_id = int(p.originalTransactionId)
	x.jws_representation = sign_jws(p)
	api_tx[str(p.transactionId)] = x.jws_representation
	return x

func _e2e_start() -> void:
	var a = phone("A")
	var b = phone("B")
	var p := tx(3000000001, "gems_500", AppleToken.for_account(str(accts.A.id)))
	e2e.ta = txn(p)
	e2e.res = {}
	a.granted.connect(func(prod, g): e2e.res["a"] = g)
	a._handle(e2e.ta)
	e2e.a = a
	e2e.b = b
	e2e.p = p

func _process(delta: float) -> bool:
	t += delta
	if api != null:
		_api_poll()
	_socks_poll()
	match phase:
		"unit":
			if answers.size() >= 14 or t > 40.0:
				_unit_checks()
				phase = "accounts"
				wait_until = t + 3.0
		"accounts":
			if t > wait_until and accts.is_empty() and socks.is_empty():
				for who in ["A", "B"]:
					var w: String = who
					ask({"t":"eco", "new":true}, func(m): accts[w] = {"id":str(m.get("acct", "")), "key":str(m.get("key", ""))})
				phase = "accounts_wait"
				wait_until = t + 20.0
		"accounts_wait":
			if accts.size() >= 2 or t > wait_until:
				check(accts.size() == 2 and str(accts.get("A", {}).get("key", "")).length() == 64, "two accounts made on the real server")
				if accts.size() < 2:
					return _finish()
				_e2e_start()
				phase = "grant"
				wait_until = t + 30.0
		"grant":
			if e2e.res.has("a") or t > wait_until:
				var g: Dictionary = e2e.res.get("a", {})
				var a = e2e.a
				check(bool(g.get("ok", false)) and int(g.get("gems", 0)) == 500 and int(g.get("profile", {}).get("gems", 0)) > 0
					and e2e.ta.finished == 1 and a.profile.iap_granted("apple:3000000001"),
					"the real server: Apple's transaction checked, 500 gems granted to the account, then finished %s" % str(g).left(160))
				# the same transaction again (a reinstall, say): "already yours"
				var a2 = phone("A")
				e2e.res2 = {}
				a2.granted.connect(func(prod, g2): e2e.res2["a"] = g2)
				var again := Txn.new()
				again.product_id = "gems_500"
				again.transaction_id = 3000000001
				again.original_id = 3000000001
				again.jws_representation = e2e.ta.jws_representation
				e2e.again = again
				a2._handle(again)
				# account B with A's transaction (its token is A's), and a copy of it without the token
				var b = e2e.b
				e2e.tb = Txn.new()
				e2e.tb.product_id = "gems_500"
				e2e.tb.transaction_id = 3000000001
				e2e.tb.original_id = 3000000001
				e2e.tb.jws_representation = e2e.ta.jws_representation
				e2e.bnotes = []
				b.note.connect(func(txt, good): e2e.bnotes.append(txt))
				b._handle(e2e.tb)
				var p2: Dictionary = (e2e.p as Dictionary).duplicate()
				p2.erase("appAccountToken")
				var b2 = phone("B")
				e2e.tc = Txn.new()
				e2e.tc.product_id = "gems_500"
				e2e.tc.transaction_id = 3000000001
				e2e.tc.original_id = 3000000001
				e2e.tc.jws_representation = sign_jws(p2)
				e2e.b2 = b2
				b2._handle(e2e.tc)
				phase = "again"
				wait_until = t + 30.0
		"again":
			var settled: bool = e2e.res2.has("a") and not e2e.b._checking.has("apple:3000000001") and not e2e.b2._checking.has("apple:3000000001")
			if settled or t > wait_until:
				var g2: Dictionary = e2e.res2.get("a", {})
				check(bool(g2.get("ok", false)) and bool(g2.get("again", false)) and e2e.again.finished == 1,
					"the same transaction again for the same account: already yours, finished %s" % str(g2).left(120))
				check(e2e.tb.finished == 0 and not e2e.b.profile.iap_granted("apple:3000000001") and (e2e.bnotes as Array).size() == 1,
					"another account sending A's transaction: refused (bought for A), not finished %s" % str(e2e.bnotes))
				check(e2e.tc.finished == 1 and not e2e.b2.profile.iap_granted("apple:3000000001"),
					"a copy without the token on another account: used (granted once, to A), finished, nothing for B")
				return _finish()
	return false

func _finish() -> bool:
	if pid > 0:
		OS.kill(pid)
	print("APPLE_IAP_PASS" if fails.is_empty() else "APPLE_IAP_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
	return true
