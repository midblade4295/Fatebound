extends Node
# 0.31.90: checks a Google Play purchase with Google before the phone grants it (Kevin: in-app purchases; the Play
# Console side is godot/PLAY_IAP_HANDOFF.md). The server holds a service-account key with access to the Google Play
# Developer API; it signs a JWT (RS256), trades it for an access token, and asks
#   GET androidpublisher/v3/applications/<pkg>/purchases/products/<product>/tokens/<token>
# Answers, through the callback: {"ok":bool, "why":String, "order":String, "test":bool}
#   ok             Google says purchased (and, for a gem pack, not consumed yet)
#   why "pending"  paid with a slow method (cash at a shop, ...); the phone waits
#   why "used"     a gem pack already consumed: granted before, never again
#   why "bad"      Google doesn't know the token / it was cancelled / refunded
#   why "unconfigured" | "unreachable"   nothing decided: the phone keeps the purchase and asks again later
#
# Key: $CREDENTIALS_DIRECTORY/play-key (systemd LoadCredential, see deploy/fatebound-siege.service), else
# SIEGE_IAP_KEY (a path), else /etc/fatebound-siege/play-service-account.json. Never in git.
# SIEGE_IAP_FAKE=1: say ok to every well-formed purchase without asking Google (internal testing only; logged loudly).
# SIEGE_IAP_API: another base URL for the purchases API (the tests' fake Google).
const Net = preload("res://scripts/siege/siege_net.gd")
const SCOPE := "https://www.googleapis.com/auth/androidpublisher"
const API := "https://androidpublisher.googleapis.com"
const KEY_FILE := "/etc/fatebound-siege/play-service-account.json"
const TIMEOUT := 12.0

var key := {}                 # the parsed service-account JSON (client_email, private_key, token_uri)
var key_from := ""
var fake := false
var api_base := API
var _access := ""
var _access_until := 0.0
var _waiting_token: Array = []      # callbacks waiting for an access token
var log_fn: Callable = func(_s): pass
var ledger_path := ""

func _init() -> void:
	fake = OS.get_environment("SIEGE_IAP_FAKE") == "1"
	if OS.has_environment("SIEGE_IAP_API"):
		api_base = OS.get_environment("SIEGE_IAP_API").trim_suffix("/")
	var path := KEY_FILE
	if OS.has_environment("CREDENTIALS_DIRECTORY") and FileAccess.file_exists(OS.get_environment("CREDENTIALS_DIRECTORY").path_join("play-key")):
		path = OS.get_environment("CREDENTIALS_DIRECTORY").path_join("play-key")
	elif OS.has_environment("SIEGE_IAP_KEY"):
		path = OS.get_environment("SIEGE_IAP_KEY")
	load_key(path)
	var state := OS.get_environment("STATE_DIRECTORY") if OS.has_environment("STATE_DIRECTORY") else "user://"
	ledger_path = state.path_join("iap_ledger.jsonl")

func load_key(path: String) -> bool:
	key = {}
	key_from = ""
	if path == "" or not FileAccess.file_exists(path):
		return false
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if v is Dictionary and str(v.get("client_email", "")) != "" and str(v.get("private_key", "")).contains("PRIVATE KEY"):
		key = v
		key_from = path
		return true
	return false

func configured() -> bool:
	return fake or not key.is_empty()

func describe() -> String:
	if fake:
		return "FAKE (every purchase accepted, testing only)"
	return ("key %s (%s)" % [key_from, str(key.client_email)]) if not key.is_empty() else "off (no service-account key)"

# ---------------- JWT (RS256) ----------------
static func b64url(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").replace("=", "")

static func make_jwt(email: String, pem: String, aud: String, now: int) -> String:
	var k := CryptoKey.new()
	if k.load_from_string(pem) != OK:
		return ""
	var head := b64url(JSON.stringify({"alg":"RS256", "typ":"JWT"}).to_utf8_buffer())
	var claims := b64url(JSON.stringify({"iss":email, "scope":SCOPE, "aud":aud, "iat":now, "exp":now + 3600}).to_utf8_buffer())
	var signing := head + "." + claims
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	hc.update(signing.to_utf8_buffer())
	var sig := Crypto.new().sign(HashingContext.HASH_SHA256, hc.finish(), k)
	if sig.is_empty():
		return ""
	return signing + "." + b64url(sig)

# ---------------- verify ----------------
func verify(product: String, token: String, cb: Callable) -> void:
	if not Net.IAP.has(product) or token.length() < 10 or token.length() > 4096:
		cb.call({"ok":false, "why":"bad"})
		return
	if fake:
		log_fn.call("IAP FAKE accept %s (SIEGE_IAP_FAKE=1)" % product)
		_ledger(product, token, {"orderId":"fake"}, "fake")
		cb.call({"ok":true, "why":"fake", "order":"fake", "test":true})
		return
	if key.is_empty():
		cb.call({"ok":false, "why":"unconfigured"})
		return
	_with_access(func(ok: bool):
		if not ok:
			cb.call({"ok":false, "why":"unreachable"})
			return
		var url := "%s/androidpublisher/v3/applications/%s/purchases/products/%s/tokens/%s" % [api_base, Net.IAP_PACKAGE,
			product.uri_encode(), token.uri_encode()]
		_http(url, HTTPClient.METHOD_GET, ["Authorization: Bearer " + _access], "", func(code: int, body: String):
			cb.call(_verdict(product, token, code, body))))

func _verdict(product: String, token: String, code: int, body: String) -> Dictionary:
	if code == 401:
		_access = ""                                  # an expired token: the next purchase asks for a new one
	if code == 401 or code == 403:
		log_fn.call("IAP Google refused the key (%d): check the service account's Play Console permissions" % code)
		return {"ok":false, "why":"unconfigured"}
	if code == 400 or code == 404 or code == 410:
		_ledger(product, token, {}, "bad %d" % code)
		return {"ok":false, "why":"bad"}
	if code != 200:
		return {"ok":false, "why":"unreachable"}
	var v: Variant = JSON.parse_string(body)
	if not (v is Dictionary):
		return {"ok":false, "why":"unreachable"}
	var g: Dictionary = v
	var order := str(g.get("orderId", ""))
	var test := g.has("purchaseType") and int(g.purchaseType) == 0       # a license tester's free purchase
	match int(g.get("purchaseState", -1)):
		0:
			pass
		2:
			return {"ok":false, "why":"pending", "order":order}
		_:
			_ledger(product, token, g, "cancelled")
			return {"ok":false, "why":"bad", "order":order}
	var once := bool((Net.IAP[product] as Dictionary).get("once", false))
	if not once and int(g.get("consumptionState", 0)) == 1:
		_ledger(product, token, g, "used")
		return {"ok":false, "why":"used", "order":order}
	_ledger(product, token, g, "ok")
	return {"ok":true, "why":"", "order":order, "test":test}

func _ledger(product: String, token: String, g: Dictionary, verdict: String) -> void:
	# One line per check (audit and refunds; the token is hashed, never stored whole).
	var f := FileAccess.open(ledger_path, FileAccess.READ_WRITE if FileAccess.file_exists(ledger_path) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify({"at":int(Time.get_unix_time_from_system()), "p":product, "tok":token.sha256_text().left(16),
		"order":str(g.get("orderId", "")), "v":verdict}))
	f.close()

# ---------------- access token ----------------
func _with_access(cb: Callable) -> void:
	var now := Time.get_unix_time_from_system()
	if _access != "" and now < _access_until:
		cb.call(true)
		return
	_waiting_token.append(cb)
	if _waiting_token.size() > 1:
		return                                        # a request is already out
	var aud := str(key.get("token_uri", "https://oauth2.googleapis.com/token"))
	var jwt := make_jwt(str(key.client_email), str(key.private_key), aud, int(now))
	if jwt == "":
		log_fn.call("IAP could not sign with the service-account key")
		_token_done(false)
		return
	var form := "grant_type=%s&assertion=%s" % ["urn:ietf:params:oauth:grant-type:jwt-bearer".uri_encode(), jwt]
	_http(aud, HTTPClient.METHOD_POST, ["Content-Type: application/x-www-form-urlencoded"], form, func(code: int, body: String):
		var v: Variant = JSON.parse_string(body) if code == 200 else null
		if v is Dictionary and str(v.get("access_token", "")) != "":
			_access = str(v.access_token)
			_access_until = Time.get_unix_time_from_system() + maxf(60.0, float(v.get("expires_in", 3600)) - 120.0)
			_token_done(true)
		else:
			log_fn.call("IAP token request failed (%d)" % code)
			_token_done(false))

func _token_done(ok: bool) -> void:
	var w := _waiting_token.duplicate()
	_waiting_token.clear()
	for cb in w:
		(cb as Callable).call(ok)

func _http(url: String, method: int, headers: Array, body: String, cb: Callable) -> void:
	var req := HTTPRequest.new()
	req.timeout = TIMEOUT
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, data: PackedByteArray):
		req.queue_free()
		cb.call(code if result == HTTPRequest.RESULT_SUCCESS else 0, data.get_string_from_utf8()))
	if req.request(url, PackedStringArray(headers), method, body) != OK:
		req.queue_free()
		cb.call(0, "")
