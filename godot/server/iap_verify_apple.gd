extends Node
# 0.31.131 (the iOS port, IOS_PORT_SPEC_FOR_CLAUDE.md §3): checks an App Store purchase before it is granted -- the
# twin of iap_verify.gd (Google, untouched). The phone (scripts/meta/billing_ios.gd) sends Apple's signed transaction
# (JWS); server/apple_jws.py, run as its own process so the game loop never waits, checks the signature chain up to
# Apple Root CA - G3 (server/certs, public) and asks Apple's App Store Server API for the same transaction. This script
# then applies the game's rules:
#   bundleId == com.fatebound.game, productId == the product asked for and in Net.IAP, not refunded (revocationDate),
#   appAccountToken (when the purchase carries one) == UUIDv5 of the account asking (scripts/meta/apple_token.gd).
# Answers, through the callback, like Google's: {"ok":bool, "why":String, "token":String, "order":String, "test":bool}
#   ok               verified (and confirmed by Apple's API); "token" is the ledger token the grant uses:
#                    "apple:<originalTransactionId>" for the starter pack (bought once), "apple:<transactionId>" else
#   why "bad"        not Apple's, not ours, refunded, another account's token, unknown to Apple
#   why "unconfigured" | "unreachable"   nothing decided: the phone keeps it (unfinished) and asks again later
# Key: $CREDENTIALS_DIRECTORY/appstore-key (systemd LoadCredential, like play-key) else SIEGE_APPSTORE_KEY (a path), plus
# SIEGE_APPSTORE_ISSUER and SIEGE_APPSTORE_KEY_ID (/etc/fatebound-siege.env). Never in git or the logs.
# SIEGE_IAP_FAKE=1: accept every well-formed purchase without checking (internal testing only; logged loudly).
# Tests: SIEGE_APPLE_TEST_ROOT (their own root, its SHA-256 next to it), SIEGE_APPSTORE_API (a fake Apple API).
const Net = preload("res://scripts/siege/siege_net.gd")
const AppleToken = preload("res://scripts/meta/apple_token.gd")
const ROOT := "res://server/certs/AppleRootCA-G3.cer"
const HELPER := "res://server/apple_jws.py"
const TIMEOUT := 25.0
const PREFIX := "apple:"

var fake := false
var key_path := ""
var issuer := ""
var key_id := ""
var root_path := ""
var root_sha256 := ""                # "" = the helper's pinned Apple root
var api_base := ""                   # "" = Apple's (production or sandbox by the transaction)
var python := "python3"
var log_fn: Callable = func(_s): pass
var ledger_path := ""
var run_fn: Callable                 # (jws, cb(helper result)) -- default: the helper process; tests may swap it
var _jobs: Array = []                # [{pid, out, jws_file, t0, cb}]
var _seq := 0

func _init() -> void:
	fake = OS.get_environment("SIEGE_IAP_FAKE") == "1"
	if OS.has_environment("CREDENTIALS_DIRECTORY") and FileAccess.file_exists(OS.get_environment("CREDENTIALS_DIRECTORY").path_join("appstore-key")):
		key_path = OS.get_environment("CREDENTIALS_DIRECTORY").path_join("appstore-key")
	elif OS.has_environment("SIEGE_APPSTORE_KEY") and FileAccess.file_exists(OS.get_environment("SIEGE_APPSTORE_KEY")):
		key_path = OS.get_environment("SIEGE_APPSTORE_KEY")
	issuer = OS.get_environment("SIEGE_APPSTORE_ISSUER").strip_edges()
	key_id = OS.get_environment("SIEGE_APPSTORE_KEY_ID").strip_edges()
	root_path = ProjectSettings.globalize_path(ROOT)
	if OS.has_environment("SIEGE_APPLE_TEST_ROOT"):
		root_path = OS.get_environment("SIEGE_APPLE_TEST_ROOT")
		root_sha256 = FileAccess.get_file_as_string(root_path.get_basename() + ".sha256").strip_edges()
	api_base = OS.get_environment("SIEGE_APPSTORE_API").strip_edges() if OS.has_environment("SIEGE_APPSTORE_API") else ""
	var state := OS.get_environment("STATE_DIRECTORY") if OS.has_environment("STATE_DIRECTORY") else "user://"
	ledger_path = state.path_join("iap_ledger.jsonl")
	run_fn = _run_helper

func configured() -> bool:
	return fake or (key_path != "" and issuer != "" and key_id != "")

func describe() -> String:
	if fake:
		return "Apple: FAKE (every purchase accepted, testing only)"
	if root_sha256 != "":
		return "Apple: TEST ROOT %s" % root_path
	if configured():
		return "Apple: key %s (issuer %s...)" % [key_id, issuer.left(8)]
	return "Apple: off (no App Store key)"

static func token_for(product: String, p: Dictionary) -> String:
	# the ledger token of a verified transaction (the phone works out the same one, billing_ios.token_of)
	var once := bool((Net.IAP.get(product, {}) as Dictionary).get("once", false))
	var n := str(p.get("originalTransactionId" if once else "transactionId", ""))
	return PREFIX + n if n.is_valid_int() and int(n) > 0 else ""

static func unverified_payload(jws: String) -> Dictionary:
	# the middle part as it says (SIEGE_IAP_FAKE only -- never trusted otherwise)
	var parts := jws.split(".")
	if parts.size() != 3:
		return {}
	var b := parts[1].replace("-", "+").replace("_", "/")
	while b.length() % 4 != 0:
		b += "="
	var v: Variant = JSON.parse_string(Marshalls.base64_to_utf8(b))
	return v if v is Dictionary else {}

# ---------------- verify ----------------
func verify(product: String, jws: String, acct: String, cb: Callable) -> void:
	if not Net.IAP.has(product) or jws.length() < 100 or jws.length() > 32768 or jws.count(".") != 2:
		cb.call({"ok":false, "why":"bad"})
		return
	if fake:
		log_fn.call("IAP FAKE accept Apple %s (SIEGE_IAP_FAKE=1)" % product)
		var fp := unverified_payload(jws)
		var r := rules(product, fp, {}, acct)
		if bool(r.ok):
			r["test"] = true
		cb.call(r)
		return
	if not configured():
		cb.call({"ok":false, "why":"unconfigured"})
		return
	run_fn.call(jws, func(res: Dictionary): cb.call(_verdict(product, acct, res)))

func _verdict(product: String, acct: String, res: Dictionary) -> Dictionary:
	if not bool(res.get("ok", false)):
		var why := str(res.get("why", ""))
		if why.begins_with("helper") or why == "root" or why == "timeout":
			log_fn.call("IAP Apple check failed (%s): nothing decided" % why)
			return {"ok":false, "why":"unreachable"}
		_ledger(product, "", {}, "bad " + why)
		return {"ok":false, "why":"bad"}
	var p: Dictionary = res.get("payload", {}) if res.get("payload", {}) is Dictionary else {}
	match str(res.get("api", "")):
		"ok":
			pass
		"notfound":
			_ledger(product, token_for(product, p), p, "bad notfound")
			return {"ok":false, "why":"bad"}
		"denied":
			log_fn.call("IAP Apple refused the App Store key: check SIEGE_APPSTORE_ISSUER / SIEGE_APPSTORE_KEY_ID and the key")
			return {"ok":false, "why":"unconfigured"}
		"off":
			return {"ok":false, "why":"unconfigured"}
		_:
			return {"ok":false, "why":"unreachable"}
	var c: Dictionary = res.get("confirmed", {}) if res.get("confirmed", {}) is Dictionary else {}
	var r := rules(product, p, c, acct)
	_ledger(product, str(r.get("token", "")), p, "ok" if bool(r.ok) else "bad " + str(r.get("rule", "")))
	r.erase("rule")
	return r

static func rules(product: String, p: Dictionary, confirmed: Dictionary, acct: String) -> Dictionary:
	# the game's rules on a transaction whose signature already checked out (p: the phone's; confirmed: Apple's API's
	# copy of the same transaction -- its refund state is the current one)
	var bad := func(rule: String) -> Dictionary: return {"ok":false, "why":"bad", "rule":rule}
	if str(p.get("bundleId", "")) != Net.IAP_PACKAGE:
		return bad.call("bundle")
	if str(p.get("productId", "")) != product or not Net.IAP.has(product):
		return bad.call("product")
	var tok := token_for(product, p)
	if tok == "":
		return bad.call("transaction id")
	if not confirmed.is_empty():
		if str(confirmed.get("transactionId", "")) != str(p.get("transactionId", "")) or str(confirmed.get("productId", "")) != product \
				or str(confirmed.get("bundleId", "")) != Net.IAP_PACKAGE:
			return bad.call("api mismatch")
	for src in [p, confirmed]:
		if float((src as Dictionary).get("revocationDate", 0)) > 0.0:
			return bad.call("refunded")
	var aat := str(p.get("appAccountToken", "")).to_lower()
	if aat != "" and aat != AppleToken.for_account(acct):
		return bad.call("account")                       # bought for another account (or none given)
	var env := str(p.get("environment", ""))
	return {"ok":true, "why":"", "token":tok, "order":str(p.get("transactionId", "")), "test":env != "Production", "rule":""}

func _ledger(product: String, token: String, p: Dictionary, verdict: String) -> void:
	# one line per decided check, in the same file as Google's (tokens hashed, never stored whole)
	var f := FileAccess.open(ledger_path, FileAccess.READ_WRITE if FileAccess.file_exists(ledger_path) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify({"at":int(Time.get_unix_time_from_system()), "p":product, "tok":token.sha256_text().left(16) if token != "" else "",
		"order":str(p.get("transactionId", "")), "v":verdict, "store":"apple", "env":str(p.get("environment", ""))}))
	f.close()

# ---------------- the helper process ----------------
func _run_helper(jws: String, cb: Callable) -> void:
	var state := ledger_path.get_base_dir()
	_seq += 1
	var base := "%s/apple_check_%d_%d" % [state, OS.get_process_id(), _seq]
	var jws_file := ProjectSettings.globalize_path(base + ".jws")
	var out := ProjectSettings.globalize_path(base + ".json")
	var f := FileAccess.open(jws_file, FileAccess.WRITE)
	if f == null:
		cb.call({"ok":false, "why":"helper write"})
		return
	f.store_string(jws)
	f.close()
	var args := PackedStringArray([ProjectSettings.globalize_path(HELPER), "--jws", jws_file, "--out", out, "--root", root_path,
		"--bundle", Net.IAP_PACKAGE])
	if root_sha256 != "":
		args.append_array(["--root-sha256", root_sha256])
	if key_path != "" and issuer != "" and key_id != "":
		args.append_array(["--key", key_path, "--issuer", issuer, "--key-id", key_id])
	if api_base != "":
		args.append_array(["--api", api_base])
	var pid := OS.create_process(python, args)
	if pid <= 0:
		DirAccess.remove_absolute(jws_file)
		cb.call({"ok":false, "why":"helper start"})
		return
	_jobs.append({"pid":pid, "out":out, "jws":jws_file, "t0":Time.get_ticks_msec() / 1000.0, "cb":cb})

func _process(_dt: float) -> void:
	for j in _jobs.duplicate():
		var done := FileAccess.file_exists(j.out)
		var late: bool = Time.get_ticks_msec() / 1000.0 - float(j.t0) > TIMEOUT
		if not done and not late and OS.is_process_running(int(j.pid)):
			continue
		_jobs.erase(j)
		var res := {}
		if done:
			var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(j.out))
			res = v if v is Dictionary else {"ok":false, "why":"helper output"}
		else:
			if OS.is_process_running(int(j.pid)):
				OS.kill(int(j.pid))
			res = {"ok":false, "why":"timeout" if late else "helper exit"}
		DirAccess.remove_absolute(j.out)
		DirAccess.remove_absolute(j.jws)
		(j.cb as Callable).call(res)
