extends Node
# 0.31.132 (the iOS port, IOS_PORT_SPEC_FOR_CLAUDE.md §4, §6): the Fatebound account between phones -- the same on
# Android and iPhone. The account (id + key, profile.d.account) is the progress; the server keeps it
# (server/eco_accounts.gd). Each request is one "eco" message with an "op" on its own socket:
#   MOVE TO ANOTHER PHONE  new_code()      a one-time 8-character code, 10 minutes (Android <-> iPhone, both ways)
#   ENTER A CODE           use_code(code)  this phone plays as that account from then on (with a key of its own)
#   Game Center            game_center()   the Game Center player is linked to the account; a reinstall gets it back
#                                          (a fresh install simply takes it; a phone with progress asks: ask_gc)
#   DELETE ACCOUNT         delete_account() the account is deleted on the server; this phone starts again
# A switch replaces this phone's account and progress with the server's (switched -> the app pulls and redraws).
const Net = preload("res://scripts/siege/siege_net.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const TIMEOUT := 20.0

signal switched                        # this phone now plays as another account (or a new one after a deletion)
signal note(text: String, good: bool)
signal ask_gc(other: Dictionary)       # Game Center has another account and this phone has progress: the app asks

var profile
var url := OS.get_environment("SIEGE_URL") if OS.has_environment("SIEGE_URL") else Net.DEFAULT_URL
var busy := ""                         # the request in flight ("" none)
var gc_done := ""                      # the Game Center player linked this run (asked once)
var _gc_other := {}                    # {acct, key, seq, sum} while the player chooses
var _gc_proof := {}
var _reqs: Array = []                  # [{ws, sent, msg, cb, t0}]

func setup(p) -> void:
	profile = p

func has_account() -> bool:
	return profile != null and str(profile.d.account.get("id", "")) != "" and str(profile.d.account.get("key", "")) != ""

func _auth() -> Dictionary:
	return {"acct":str(profile.d.account.get("id", "")), "key":str(profile.d.account.get("key", ""))}

# ---------------- MOVE TO ANOTHER PHONE / ENTER A CODE ----------------
func new_code(cb: Callable) -> void:
	# cb({ok, code, ttl} | {ok:false, why: "auth" | "busy" | "old" | "unreachable"})
	if not has_account():
		cb.call({"ok":false, "why":"auth"})
		return
	var m := {"t":"eco", "v":Net.VERSION, "op":"link_new"}
	m.merge(_auth())
	_ask("code", m, func(a: Dictionary):
		if bool(a.get("ok", false)) and not a.has("code"):
			a = {"ok":false, "why":"old"}            # (a server from before 0.31.132 answered with the account)
		cb.call(a))

func use_code(code: String, cb: Callable) -> void:
	# cb({ok} | {ok:false, why: "code" | "busy" | "old" | "unreachable"}); on ok this phone has switched
	var c := code.strip_edges().to_upper().replace(" ", "").replace("-", "")
	if c.length() != 8:
		cb.call({"ok":false, "why":"code"})
		return
	_ask("use", {"t":"eco", "v":Net.VERSION, "op":"link_use", "code":c}, func(a: Dictionary):
		if bool(a.get("ok", false)) and str(a.get("acct", "")) != "" and str(a.get("key", "")).length() == 64:
			switch_to(str(a.acct), str(a.key), int(a.get("seq", 0)))
			cb.call({"ok":true})
			return
		if bool(a.get("ok", false)):
			a = {"ok":false, "why":"old"}
		cb.call(a))

# ---------------- DELETE ACCOUNT ----------------
func delete_account(cb: Callable) -> void:
	# cb({ok} | {ok:false, why}); on ok the phone's progress is gone too and a new account comes with the next sync
	if not has_account():
		cb.call({"ok":false, "why":"auth"})
		return
	var m := {"t":"eco", "v":Net.VERSION, "op":"delete"}
	m.merge(_auth())
	_ask("delete", m, func(a: Dictionary):
		if bool(a.get("ok", false)) and str(a.get("op", "")) == "delete":
			wipe()
			cb.call({"ok":true})
			return
		if bool(a.get("ok", false)):
			a = {"ok":false, "why":"old"}
		cb.call(a))

func wipe() -> void:
	# this phone starts again: a fresh profile (its sound and graphics settings kept); the Google Play copy, if any,
	# is overwritten by the fresh one at its next upload (marked changed), never read back
	var keep: Dictionary = profile.d.settings.duplicate(true)
	var cloud: Dictionary = profile.d.cloud.duplicate(true)
	profile.d = Profile.defaults()
	profile.d.settings = keep
	profile.d.cloud = {"stamp":str(cloud.get("stamp", "")), "dirty":true, "at":int(cloud.get("at", 0))}
	profile.save(false)
	switched.emit()

# ---------------- Game Center ----------------
func game_center(team_id: String, proof: Dictionary) -> void:
	# the Game Center player and Apple's identity signature ({url, data, salt, timestamp} from GKLocalPlayer)
	if team_id == "" or gc_done == team_id or busy != "":
		return
	var sig: Variant = proof.get("data", PackedByteArray())
	var salt: Variant = proof.get("salt", PackedByteArray())
	if not (sig is PackedByteArray) or not (salt is PackedByteArray) or (sig as PackedByteArray).is_empty():
		return
	_gc_proof = {"id":team_id, "url":str(proof.get("url", "")), "sig":Marshalls.raw_to_base64(sig),
		"salt":Marshalls.raw_to_base64(salt), "ts":int(proof.get("timestamp", 0))}
	var m := {"t":"eco", "v":Net.VERSION, "op":"gc", "gc":_gc_proof}
	if has_account():
		m.merge(_auth())
	_ask("gc", m, func(a: Dictionary): _on_gc(team_id, a))

func _on_gc(team_id: String, a: Dictionary) -> void:
	if not bool(a.get("ok", false)):
		return                                       # (offline, an older server, a refused signature: next start)
	match str(a.get("gc", "")):
		"linked", "same":
			gc_done = team_id
		"none":
			pass                                     # (no account here yet: linked once eco_sync has made one)
		"other":
			gc_done = team_id
			var other := {"acct":str(a.get("acct", "")), "key":str(a.get("key", "")), "seq":int(a.get("seq", 0)),
				"sum":a.get("sum", {}) if a.get("sum", {}) is Dictionary else {}}
			if str(other.acct) == "" or str(other.key).length() != 64:
				return
			if not has_account() or profile.is_fresh():
				switch_to(str(other.acct), str(other.key), int(other.seq))
				note.emit("Progress restored from Game Center", true)
			else:
				_gc_other = other
				ask_gc.emit(other)

func choose_gc(use_other: bool) -> void:
	# the answer to ask_gc: USE THAT ACCOUNT (this phone switches) or KEEP THIS PHONE'S (Game Center follows this one)
	if _gc_other.is_empty():
		return
	var o := _gc_other
	_gc_other = {}
	if use_other:
		switch_to(str(o.acct), str(o.key), int(o.seq))
		note.emit("Progress restored from Game Center", true)
		return
	# a fresh signature is needed (each is used once): Game Center gives one at the next sign-in or start
	gc_done = ""
	_pending_relink = true

var _pending_relink := false

func relink_pending() -> bool:
	return _pending_relink

func game_center_relink(team_id: String, proof: Dictionary) -> void:
	# KEEP THIS PHONE'S, with a fresh identity signature
	if not _pending_relink or not has_account():
		return
	_pending_relink = false
	var sig: Variant = proof.get("data", PackedByteArray())
	var salt: Variant = proof.get("salt", PackedByteArray())
	if not (sig is PackedByteArray) or not (salt is PackedByteArray):
		return
	var g := {"id":team_id, "url":str(proof.get("url", "")), "sig":Marshalls.raw_to_base64(sig),
		"salt":Marshalls.raw_to_base64(salt), "ts":int(proof.get("timestamp", 0))}
	var m := {"t":"eco", "v":Net.VERSION, "op":"gc", "gc":g, "relink":true}
	m.merge(_auth())
	_ask("gc", m, func(a: Dictionary):
		if bool(a.get("ok", false)):
			gc_done = team_id
			note.emit("Game Center now goes with this phone's progress", true))

func pending_gc() -> Dictionary:
	return _gc_other

# ---------------- the switch ----------------
func switch_to(acct: String, key: String, seq: int) -> void:
	# this phone plays as that account from now on: the server's copy replaces the phone's at the next sync (the app
	# pulls at once); ops numbered after the account's own (seq), so none is mistaken for one already done
	profile.d.account = {"id":acct, "key":key, "seq":seq}
	profile.d.cloud["dirty"] = true                  # (Google Play's copy follows the account)
	profile.save(false)
	switched.emit()

# ---------------- the socket ----------------
func _ask(what: String, msg: Dictionary, cb: Callable) -> void:
	var ws := WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 21
	if ws.connect_to_url(url) != OK:
		cb.call({"ok":false, "why":"unreachable"})
		return
	busy = what
	_reqs.append({"ws":ws, "sent":false, "msg":msg, "cb":cb, "t0":Time.get_ticks_msec() / 1000.0})

func _process(_dt: float) -> void:
	for r in _reqs.duplicate():
		var ws: WebSocketPeer = r.ws
		ws.poll()
		var st := ws.get_ready_state()
		if st == WebSocketPeer.STATE_OPEN and not r.sent:
			ws.put_packet(Net.encode(r.msg, true))
			r.sent = true
		var answer := {}
		while ws.get_available_packet_count() > 0:
			var m := Net.decode(ws.get_packet())
			if str(m.get("t", "")) == "eco":
				answer = m
		var late: bool = Time.get_ticks_msec() / 1000.0 - float(r.t0) > TIMEOUT
		if not answer.is_empty() or st == WebSocketPeer.STATE_CLOSED or late:
			_reqs.erase(r)
			if st != WebSocketPeer.STATE_CLOSED:
				ws.close()
			if _reqs.is_empty():
				busy = ""
			(r.cb as Callable).call(answer if not answer.is_empty() else {"ok":false, "why":"unreachable"})
