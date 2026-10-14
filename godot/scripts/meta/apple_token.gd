extends RefCounted
# 0.31.130 (the iOS port, IOS_PORT_SPEC_FOR_CLAUDE.md §3): the appAccountToken an App Store purchase carries -- which
# Fatebound account bought it. A UUID version 5 (RFC 9562: SHA-1 of a namespace and a name) of the server account's id,
# so the phone (scripts/meta/billing_ios.gd) and the server (server/iap_verify_apple.gd) each work it out alone and the
# server refuses a purchase whose token isn't the account's. Nothing secret: it only binds a purchase to an account.
#   python3 -c "import uuid; print(uuid.uuid5(uuid.UUID('14e4328b-9f9f-5cb3-932f-4b0af036d9b0'), '<account id>'))"
# NAMESPACE is uuid5(NAMESPACE_DNS, "account.fatebound.game"); never change it (old purchases carry tokens made with it).
const NAMESPACE := "14e4328b-9f9f-5cb3-932f-4b0af036d9b0"

static func for_account(acct: String) -> String:
	if acct == "":
		return ""
	return uuid5(NAMESPACE, acct)

static func uuid5(ns: String, name: String) -> String:
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA1)
	hc.update(ns.replace("-", "").hex_decode())
	hc.update(name.to_utf8_buffer())
	var b := hc.finish().slice(0, 16)
	b[6] = (b[6] & 0x0f) | 0x50                  # version 5
	b[8] = (b[8] & 0x3f) | 0x80                  # the RFC variant
	var h := b.hex_encode()
	return "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12)]
