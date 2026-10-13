extends Node
# 0.31.111 (Kevin: "Build a global chat and players can click a name and have option to add friend to a friends list.
# They can then group up and form a party"): the phone's social side -- one WebSocket to the Siege server while the
# app is up (server/social.gd is the other end and has the rules). It needs the account (eco_sync.gd): without one, or
# against a server older than 0.31.111 (it never answers "hi"), it stays off and the screens say so.
# The app sets `want` (in front, account ready); this keeps the connection, retrying with a growing wait, and holds
# what the screens show: the chat lines, friends, requests, the party and invites. Every change emits `changed`.
const Net = preload("res://scripts/siege/siege_net.gd")

signal changed(what: String)            # "state", "me", "chat", "friends", "party"
signal note(text: String, bad: bool, pop: bool)
signal request(card: Dictionary)        # someone wants to be friends
signal invited(party: String, card: Dictionary)
signal go(party: String, by: String)    # the party leader started a match

const RETRY := [2.0, 5.0, 10.0, 20.0, 40.0, 60.0]
const OLD_SERVER_RETRY := 600.0         # s before asking a server that never answered "hi" again
const HI_TIMEOUT := 8.0
const KEEP := 100                       # lines kept a channel
const INVITE_LIFE := 60.0

var url := OS.get_environment("SIEGE_URL") if OS.has_environment("SIEGE_URL") else Net.DEFAULT_URL
var profile
var want := false
var state := "off"                      # off / connecting / online / old (no social side on the server)
var me := {}                            # {"pid", "n", "tt", "max"}
var lines := {"global": [], "party": []}
var unread := {"global": 0, "party": 0}
var viewing := ""                       # the chat tab on screen ("" = closed): its lines count as read
var show_global := true                 # the player's setting (Settings): global chat off keeps friends and parties
var friends: Array = []                 # cards {"pid", "n", "tt", "st", "seen"}
var rin: Array = []                     # requests to me
var rout: Array = []                    # my requests
var blocked: Array = []
var party: Dictionary = {}              # {} or {"id", "leader", "members", "pending", "max"}
var invites: Dictionary = {}            # party id -> {"from": card, "at": clock}
var party_play := ""                    # the party a "go" was for (siege_app passes it into the match)
var _ws: WebSocketPeer = null
var _clock := 0.0
var _next_try := 0.0
var _fails := 0
var _t0 := 0.0
var _hi_sent := false

func setup(p) -> void:
	profile = p

func has_account() -> bool:
	return profile != null and str(profile.d.account.get("id", "")) != "" and str(profile.d.account.get("key", "")) != ""

func set_active(on: bool) -> void:
	want = on
	if not on:
		_close()
	elif _ws == null and state != "old":
		_next_try = minf(_next_try, _clock)

func online() -> bool:
	return state == "online"

func _process(delta: float) -> void:
	_clock += delta
	for pa in invites.keys():
		if _clock - float(invites[pa].at) > INVITE_LIFE:
			invites.erase(pa)
			changed.emit("party")
	if _ws == null:
		if want and has_account() and _clock >= _next_try:
			_open()
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and not _hi_sent:
		_hi_sent = true
		_t0 = _clock
		var hi := {"t":"so", "k":"hi", "v":Net.VERSION, "acct":str(profile.d.account.id), "key":str(profile.d.account.key)}
		if not bool(profile.d.settings.get("analytics", true)):
			hi["an_off"] = 1                         # 0.31.118: usage statistics off -- the server writes nothing for us
		_ws.put_packet(Net.encode(hi))
	while _ws != null and _ws.get_available_packet_count() > 0:
		_on(Net.decode(_ws.get_packet()))
	if _ws == null:
		return
	if st == WebSocketPeer.STATE_CLOSED:
		_lost()
	elif state == "connecting" and _clock - _t0 > HI_TIMEOUT:
		# the server never answered: one without a social side (older than 0.31.111) -- ask again much later
		_close()
		state = "old"
		_next_try = _clock + OLD_SERVER_RETRY
		changed.emit("state")

func _open() -> void:
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 20
	_ws.outbound_buffer_size = 1 << 16
	_hi_sent = false
	_t0 = _clock
	state = "connecting"
	if _ws.connect_to_url(url) != OK:
		_ws = null
		_lost()
		return
	changed.emit("state")

func _lost() -> void:
	_ws = null
	if state != "old":
		state = "off"
	_fails += 1
	_next_try = _clock + float(RETRY[mini(_fails - 1, RETRY.size() - 1)])
	changed.emit("state")

func _close() -> void:
	if _ws != null:
		_ws.close()
	_ws = null
	if state != "old":
		state = "off"
	changed.emit("state")

func _send(msg: Dictionary) -> bool:
	if state != "online" or _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	msg["t"] = "so"
	_ws.put_packet(Net.encode(msg))
	return true

# ---------------- what the server says ----------------
func _on(m: Dictionary) -> void:
	if str(m.get("t", "")) != "so":
		return
	match str(m.get("k", "")):
		"me":
			me = {"pid":str(m.get("pid", "")), "n":str(m.get("n", "")), "tt":str(m.get("tt", "")), "max":int(m.get("max", 120))}
			var was := state
			state = "online"
			_fails = 0
			changed.emit("me")
			if was != "online":
				changed.emit("state")
		"bye":
			# "auth": the account isn't known here (eco_sync makes a new one); "replaced": this account opened another
			# social socket (a second copy of the app) -- either way, try again later rather than fight over it
			_close()
			_next_try = _clock + (60.0 if str(m.get("why", "")) == "replaced" else 20.0)
		"hist":
			var ch := str(m.get("ch", "global"))
			if ch == "global" and not show_global:
				return
			var l: Array = m.get("list", [])
			lines[ch] = l.slice(maxi(0, l.size() - KEEP))
			changed.emit("chat")
		"chat":
			var line: Dictionary = m.get("m", {})
			var ch := str(line.get("ch", "global"))
			if not lines.has(ch) or (ch == "global" and not show_global):
				return
			var l: Array = lines[ch]
			l.append(line)
			while l.size() > KEEP:
				l.pop_front()
			if viewing != ch and str(line.get("pid", "")) != str(me.get("pid", "")):
				unread[ch] = int(unread[ch]) + 1
			changed.emit("chat")
		"friends":
			friends = m.get("friends", [])
			rin = m.get("rin", [])
			rout = m.get("rout", [])
			blocked = m.get("blocked", [])
			changed.emit("friends")
		"pres":
			var c: Dictionary = m.get("c", {})
			for l in [friends, rin, rout]:
				for i in (l as Array).size():
					if str(l[i].pid) == str(c.get("pid", "")):
						l[i] = c
			changed.emit("friends")
		"req":
			request.emit(m.get("from", {}))
		"party":
			var p: Variant = m.get("party", {})
			party = p if p is Dictionary else {}
			if party.is_empty():
				lines.party = []
				unread.party = 0
			changed.emit("party")
		"inv":
			var pa := str(m.get("party", ""))
			invites[pa] = {"from":m.get("from", {}), "at":_clock}
			invited.emit(pa, m.get("from", {}))
			changed.emit("party")
		"go":
			party_play = str(m.get("party", ""))
			go.emit(party_play, str(m.get("by", "")))
		"note":
			note.emit(str(m.get("x", "")), bool(m.get("bad", false)), bool(m.get("pop", false)))

# ---------------- what the player does ----------------
func say(ch: String, text: String) -> bool:
	var t := text.strip_edges()
	if t == "":
		return false
	return _send({"k":"chat", "ch":ch, "x":t.left(int(me.get("max", 120)))})

func add(pid: String) -> bool:
	return _send({"k":"add", "pid":pid.strip_edges().to_lower()})

func decline(pid: String) -> bool:
	return _send({"k":"decline", "pid":pid})

func unfriend(pid: String) -> bool:
	return _send({"k":"unfriend", "pid":pid})

func block(pid: String) -> bool:
	return _send({"k":"block", "pid":pid})

func unblock(pid: String) -> bool:
	return _send({"k":"unblock", "pid":pid})

func report(pid: String, why: String) -> bool:
	return _send({"k":"report", "pid":pid, "why":why})

func invite(pid: String) -> bool:
	return _send({"k":"invite", "pid":pid})

func join(pa: String) -> bool:
	invites.erase(pa)
	changed.emit("party")
	return _send({"k":"join", "party":pa})

func no_join(pa: String) -> bool:
	invites.erase(pa)
	changed.emit("party")
	return _send({"k":"nojoin", "party":pa})

func leave() -> bool:
	return _send({"k":"leave"})

func kick(pid: String) -> bool:
	return _send({"k":"kick", "pid":pid})

func play() -> bool:
	return _send({"k":"play"})

func refresh() -> bool:
	return _send({"k":"refresh"})

func mark_read(ch: String) -> void:
	if int(unread.get(ch, 0)) != 0:
		unread[ch] = 0
		changed.emit("chat")

func set_show_global(on: bool) -> void:
	show_global = on
	if not on:
		lines.global = []
		unread.global = 0
	changed.emit("chat")

# ---------------- for the screens ----------------
func in_party() -> bool:
	return not party.is_empty()

func is_leader() -> bool:
	return in_party() and str(party.get("leader", "")) == str(me.get("pid", ""))

func party_size() -> int:
	return (party.get("members", []) as Array).size()

func in_my_party(pid: String) -> bool:
	for c in party.get("members", []):
		if str(c.pid) == pid:
			return true
	return false

func relation(pid: String) -> String:
	# "me", "friend", "sent" (I asked), "asked" (they asked me), "blocked" or "none"
	if pid == str(me.get("pid", "")):
		return "me"
	for pair in [[friends, "friend"], [rin, "asked"], [rout, "sent"], [blocked, "blocked"]]:
		for c in pair[0]:
			if str(c.pid) == pid:
				return pair[1]
	return "none"

func card_of(pid: String) -> Dictionary:
	for l in [friends, rin, rout, blocked, party.get("members", [])]:
		for c in l:
			if str(c.pid) == pid:
				return c
	return {}

func attention() -> int:
	# the Home badge: friend requests and party invites waiting
	return rin.size() + invites.size()

func unread_total() -> int:
	return int(unread.global) + int(unread.party)

static func code_of(pid: String) -> String:
	return pid.to_upper()
