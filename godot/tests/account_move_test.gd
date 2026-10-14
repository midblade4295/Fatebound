extends SceneTree
# 0.31.132 the iOS port, step 6/9 (IOS_PORT_SPEC_FOR_CLAUDE.md §4, §6): the account between phones. REAL time.
#  1. server/eco_accounts.gd alone: a transfer code (8 characters, 10 minutes, once, a key of its own for the new phone,
#     the old phone's key still works), limits (codes an hour, wrong codes); the Game Center link (linked, same,
#     another account found with a key, relink, a deleted account's link); deleting an account (files, keys, links
#     gone; purchase tokens still guarded).
#  2. The real server (8116) with scripts/meta/account_link.gd on two "phones": MOVE TO ANOTHER PHONE on one, ENTER A
#     CODE on the other -> the same account; a wrong code; Game Center: phone A links its player, a fresh phone B with
#     the same player takes A's account (Apple's identity signature checked by the helper against a stand-in key
#     server on 8117), the same signature again is refused; DELETE ACCOUNT: gone on the server, the phone starts afresh.
#   godot --headless --path godot -s res://tests/account_move_test.gd
const Net = preload("res://scripts/siege/siege_net.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const Accounts = preload("res://server/eco_accounts.gd")
const AccountLink = preload("res://scripts/meta/account_link.gd")

const SRV_PORT := 8116
const KEYS_PORT := 8117
const BUNDLE := "com.fatebound.game"

var fails: Array = []
var phase := "boot"
var t := 0.0
var wait_until := 0.0
var pid := -1
var dir := ""
var keys: TCPServer = null
var key_peers: Array = []
var key_hits := 0
var socks: Array = []
var got := {}
var phones := {}

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func tool(args: Array) -> String:
	var out := []
	OS.execute("python3", [ProjectSettings.globalize_path("res://tools/apple_test_certs.py")] + args, out, true)
	return str(out[0]).strip_edges() if not out.is_empty() else ""

func _init() -> void:
	_unit()
	dir = ProjectSettings.globalize_path("user://account_move_test_%d" % Time.get_ticks_usec())
	check(tool(["make", dir]) == "TEST_APPLE_OK", "a stand-in for Apple's Game Center key server")
	keys = TCPServer.new()
	check(keys.listen(KEYS_PORT, "127.0.0.1") == OK, "its key server on %d" % KEYS_PORT)
	var state := ProjectSettings.globalize_path("user://account_move_state_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(state)
	OS.set_environment("SIEGE_PORT", str(SRV_PORT))
	OS.set_environment("SIEGE_HOST", "127.0.0.1")
	OS.set_environment("STATE_DIRECTORY", state)
	OS.set_environment("SIEGE_APPLE_TEST_ROOT", dir.path_join("root.cer"))
	OS.set_environment("SIEGE_IAP_KEY", "/nonexistent/key.json")
	pid = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://server/siege_server.gd"])
	OS.unset_environment("STATE_DIRECTORY")
	wait_until = 3.0

# ---------------- 1. the accounts alone ----------------
func _unit() -> void:
	var tmp := ProjectSettings.globalize_path("user://account_move_unit_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	var acc = Accounts.new(tmp)
	acc.now_override = 1791000000
	var a: Dictionary = acc.handle({"t":"eco", "new":true})
	var b: Dictionary = acc.handle({"t":"eco", "new":true})
	var aid := str(a.acct)
	var akey := str(a.key)
	var c: Dictionary = acc.link_new(aid, akey)
	var code := str(c.get("code", ""))
	var only_ok := true
	for ch in code:
		only_ok = only_ok and Accounts.LINK_CHARS.contains(ch)
	check(bool(c.ok) and code.length() == 8 and only_ok and int(c.ttl) == 600, "MOVE TO ANOTHER PHONE: an 8-character code for 10 minutes (%s)" % code)
	check(not bool(acc.link_new(aid, "0".repeat(64)).ok), "only with the account's key")
	var u: Dictionary = acc.link_use(code.to_lower().insert(4, " - "), "1.2.3.4")
	var nkey := str(u.get("key", ""))
	check(bool(u.ok) and str(u.acct) == aid and nkey.length() == 64 and nkey != akey and int(u.seq) >= 0 and u.get("profile", {}).has("stats"),
		"ENTER A CODE (spaces, dashes and case don't matter): the account, with a key of its own and the account as it stands")
	check(not acc.open(aid, nkey).is_empty() and not acc.open(aid, akey).is_empty(), "the new phone's key opens it; the first phone's still does")
	check(str(acc.link_use(code, "1.2.3.4").get("why", "")) == "code", "a code works once")
	var c2: Dictionary = acc.link_new(aid, akey)
	acc.now_override = 1791000000 + 601
	check(str(acc.link_use(str(c2.code), "1.2.3.5").get("why", "")) == "code", "a code runs out after 10 minutes")
	acc.now_override = 1791000000 + 700
	var made := 0
	for i in 6:
		if bool(acc.link_new(aid, akey).ok):
			made += 1
	check(made == 3, "at most 5 codes an hour per account (2 made before, %d more)" % made)
	var tries := []
	for i in 11:
		tries.append(str(acc.link_use("AAAA2222", "9.9.9.9").get("why", "")))
	check(tries.slice(0, 10).all(func(x): return x == "code") and tries[10] == "busy", "10 wrong codes from one address, then busy")
	# Game Center
	var g1: Dictionary = acc.gc_link(aid, akey, "T:111")
	var g2: Dictionary = acc.gc_link(aid, nkey, "T:111")
	check(str(g1.gc) == "linked" and str(g2.gc) == "same" and not FileAccess.get_file_as_string(tmp.path_join("gc_links.json")).contains("T:111"),
		"Game Center player linked (only its hash kept); the account's other phone: the same")
	var g3: Dictionary = acc.gc_link(str(b.acct), str(b.key), "T:111")
	check(str(g3.gc) == "other" and str(g3.acct) == aid and not acc.open(aid, str(g3.key)).is_empty() and g3.get("sum", {}).has("level"),
		"another account with the same Game Center player: A's account offered, with a key that opens it")
	var g4: Dictionary = acc.gc_link("", "", "T:111")
	check(str(g4.gc) == "other" and str(g4.acct) == aid, "no account yet (a reinstall): A's account offered")
	check(str(acc.gc_link("", "", "T:222").gc) == "none", "an unknown player and no account: none")
	var g5: Dictionary = acc.gc_link(str(b.acct), str(b.key), "T:111", true)
	check(str(g5.gc) == "linked" and str(acc.gc_link("", "", "T:111").acct) == str(b.acct), "KEEP THIS PHONE'S: the player now goes with B")
	# delete
	var tok := "apple:9000000001"
	var gp: Dictionary = acc.grant_purchase(aid, akey, "gems_80", tok)
	var d: Dictionary = acc.delete_account(aid, akey)
	check(bool(gp.ok) and bool(d.ok) and acc.open(aid, nkey).is_empty() and not FileAccess.file_exists(tmp.path_join("accounts/%s.meta.json" % aid))
		and not FileAccess.file_exists(tmp.path_join("accounts/%s.json" % aid)), "DELETE ACCOUNT: its files gone, no key opens it")
	check(str(acc.grant_purchase(str(b.acct), str(b.key), "gems_80", tok).get("why", "")) == "used", "a deleted account's purchase can't be granted to anyone else")
	check(not bool(acc.delete_account(aid, akey).ok), "deleting it again: refused (auth)")
	var bg: Dictionary = acc.gc_link(str(b.acct), str(b.key), "T:333")
	acc.delete_account(str(b.acct), str(b.key))
	check(str(bg.gc) == "linked" and str(acc.gc_link("", "", "T:333").gc) == "none", "a deleted account's Game Center link is gone too")

# ---------------- the stand-in key server ----------------
func _keys_poll() -> void:
	while keys.is_connection_available():
		key_peers.append({"c":keys.take_connection(), "buf":PackedByteArray()})
	for kp in key_peers.duplicate():
		var c: StreamPeerTCP = kp.c
		c.poll()
		var n := c.get_available_bytes()
		if n > 0:
			var b: PackedByteArray = kp.buf
			b.append_array(c.get_data(n)[1])
			kp.buf = b
		if not (kp.buf as PackedByteArray).get_string_from_utf8().contains("\r\n\r\n"):
			continue
		key_hits += 1
		var body := FileAccess.get_file_as_bytes(dir.path_join("gc.cer"))
		var head := "HTTP/1.1 200 OK\r\nContent-Type: application/pkix-cert\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % body.size()
		c.put_data(head.to_utf8_buffer() + body)
		c.disconnect_from_host()
		key_peers.erase(kp)

func proof(team: String) -> Dictionary:
	var salt := Crypto.new().generate_random_bytes(16)
	var ts := int(Time.get_unix_time_from_system() * 1000.0)
	var sig := tool(["gc-sign", dir, team, BUNDLE, str(ts), Marshalls.raw_to_base64(salt)])
	return {"url":"http://127.0.0.1:%d/public-key/gc-prod-10.cer" % KEYS_PORT, "data":Marshalls.base64_to_raw(sig), "salt":salt, "timestamp":ts}

# ---------------- 2. phones against the real server ----------------
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

func phone(who: String, acct := {}) -> Node:
	var p = Profile.new("user://account_move_%s_%d.json" % [who, Time.get_ticks_usec()], "user://none.json")
	p.load_or_create()
	if not acct.is_empty():
		p.d.account = {"id":str(acct.acct), "key":str(acct.key), "seq":0}
		p.server_mode = true
	var l = AccountLink.new()
	l.url = "ws://127.0.0.1:%d/fatebound/siege/ws" % SRV_PORT
	root.add_child(l)
	l.setup(p)
	var rec := {"switched":0, "notes":[], "ask":[]}
	l.switched.connect(func(): rec.switched += 1)
	l.note.connect(func(x, _g): rec.notes.append(x))
	l.ask_gc.connect(func(o): rec.ask.append(o))
	l.set_meta("rec", rec)
	phones[who] = l
	return l

func _process(delta: float) -> bool:
	t += delta
	if keys != null:
		_keys_poll()
	_socks_poll()
	match phase:
		"boot":
			if t > wait_until:
				for who in ["A", "B", "C"]:
					var w: String = who
					ask({"t":"eco", "new":true}, func(m): got[w] = m)
				phase = "accounts"
				wait_until = t + 20.0
		"accounts":
			if got.size() >= 3 or t > wait_until:
				check(got.size() == 3 and str(got.get("A", {}).get("key", "")).length() == 64, "three accounts on the real server")
				if got.size() < 3:
					return _finish()
				var a := phone("A", got.A)
				a.new_code(func(r): got["code"] = r)
				phase = "code"
				wait_until = t + 20.0
		"code":
			if got.has("code") or t > wait_until:
				var r: Dictionary = got.get("code", {})
				check(bool(r.get("ok", false)) and str(r.get("code", "")).length() == 8, "MOVE TO ANOTHER PHONE over the socket: %s" % str(r))
				var b := phone("B2")
				b.use_code("WRONG234", func(x): got["wrong"] = x)
				var b2 := phone("B")
				b2.use_code(str(r.get("code", "")), func(x): got["use"] = x)
				phase = "use"
				wait_until = t + 20.0
		"use":
			if (got.has("use") and got.has("wrong")) or t > wait_until:
				var b: Node = phones.B
				var rec: Dictionary = b.get_meta("rec")
				check(bool(got.get("use", {}).get("ok", false)) and int(rec.switched) == 1 and str(b.profile.d.account.id) == str(got.A.acct)
					and str(b.profile.d.account.key) != str(got.A.key) and bool(b.profile.d.cloud.dirty),
					"ENTER A CODE on the other phone: it plays as A's account now, with its own key")
				check(str(got.get("wrong", {}).get("why", "")) == "code" and int(phones.B2.get_meta("rec").switched) == 0, "a wrong code: refused, nothing switched")
				# Game Center: A links its player; a fresh phone with the same player takes A's account
				var pr := proof("T:gc-player-1")
				got["proof"] = pr
				phones.A.game_center("T:gc-player-1", pr)
				phase = "gc_a"
				wait_until = t + 20.0
		"gc_a":
			if phones.A.gc_done != "" or t > wait_until:
				check(phones.A.gc_done == "T:gc-player-1" and key_hits >= 1, "Game Center: A's player linked (Apple's signature checked with the key server's certificate)")
				var c := phone("C", got.C)
				c.game_center("T:gc-player-1", proof("T:gc-player-1"))
				var r2 := phone("R", got.C)
				r2.game_center("T:gc-player-1", got.proof)          # the very same signature again
				var f := phone("F", got.C)
				var forged: Dictionary = proof("T:gc-player-1")
				f.game_center("T:someone-else", forged)              # signed for another player
				phase = "gc_c"
				wait_until = t + 20.0
		"gc_c":
			var done: bool = phones.C.busy == "" and phones.R.busy == "" and phones.F.busy == ""
			if (done and t > wait_until - 19.0) or t > wait_until:
				var c: Node = phones.C
				check(int(c.get_meta("rec").switched) == 1 and str(c.profile.d.account.id) == str(got.A.acct) and (c.get_meta("rec").notes as Array).has("Progress restored from Game Center"),
					"a fresh phone with the same Game Center player: A's account restored, no question asked")
				check(int(phones.R.get_meta("rec").switched) == 0 and phones.R.gc_done == "", "the same signature twice: refused (used once)")
				check(int(phones.F.get_meta("rec").switched) == 0 and phones.F.gc_done == "", "a signature for another player: refused")
				# DELETE ACCOUNT from phone B (A's account)
				phones.B.delete_account(func(x): got["del"] = x)
				phase = "delete"
				wait_until = t + 20.0
		"delete":
			if got.has("del") or t > wait_until:
				var b: Node = phones.B
				check(bool(got.get("del", {}).get("ok", false)) and str(b.profile.d.account.get("id", "")) == "" and int(b.get_meta("rec").switched) == 2,
					"DELETE ACCOUNT: done on the server, the phone starts afresh")
				ask({"t":"eco", "acct":str(got.A.acct), "key":str(got.A.key)}, func(m): got["after"] = m)
				phase = "after"
				wait_until = t + 20.0
		"after":
			if got.has("after") or t > wait_until:
				check(str(got.get("after", {}).get("why", "")) == "auth", "the first phone's key no longer opens the deleted account")
				return _finish()
	return false

func _finish() -> bool:
	if pid > 0:
		OS.kill(pid)
	print("ACCOUNT_MOVE_PASS" if fails.is_empty() else "ACCOUNT_MOVE_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
	return true
