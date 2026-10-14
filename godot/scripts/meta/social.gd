extends Node
# 0.31.111 (Kevin: "Build a global chat and players can click a name and have option to add friend to a friends list.
# They can then group up and form a party"): the phone's social side -- one WebSocket to the Siege server while the
# app is up (server/social.gd is the other end and has the rules). It needs the account (eco_sync.gd): without one, or
# against a server older than 0.31.111 (it never answers "hi"), it stays off and the screens say so.
# The app sets `want` (in front, account ready); this keeps the connection, retrying with a growing wait, and holds
# what the screens show: the chat lines, friends, requests, the party and invites. Every change emits `changed`.
# 0.31.134 (Crown War step 1): clans (server/clans.gd) -- the player's clan, invites, search results, a clan's card,
# and the "clan" chat channel; cards and lines carry "ct", a player's clan tag. "me" says "clans":1 when the server
# has them.
const Net = preload("res://scripts/siege/siege_net.gd")

signal changed(what: String)            # "state", "me", "chat", "friends", "party", "prof" (0.31.120), "clan", "clans", "clan_info" (0.31.134)
signal note(text: String, bad: bool, pop: bool)
signal request(card: Dictionary)        # someone wants to be friends
signal invited(party: String, card: Dictionary)
signal go(party: String, by: String)    # the party leader started a match
signal clan_invited(c: Dictionary, by: Dictionary)   # 0.31.134: an officer of a clan invited this player
signal clan_made(ok: bool, why: String)              # 0.31.134: the answer to clan_new (ok: the gold was taken)

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
var lines := {"global": [], "party": [], "clan": []}
var unread := {"global": 0, "party": 0, "clan": 0}
var viewing := ""                       # the chat tab on screen ("" = closed): its lines count as read
var show_global := true                 # the player's setting (Settings): global chat off keeps friends and parties
var friends: Array = []                 # cards {"pid", "n", "tt", "st", "seen"}
var rin: Array = []                     # requests to me
var rout: Array = []                    # my requests
var blocked: Array = []
var party: Dictionary = {}              # {} or {"id", "leader", "members", "pending", "max"}
var invites: Dictionary = {}            # party id -> {"from": card, "at": clock}
var party_play := ""                    # the party a "go" was for (siege_app passes it into the match)
var profiles := {}                      # 0.31.120: pid -> its profile card's numbers ({"t":"so", "k":"prof", ...}, "_at": clock)
# 0.31.134: clans
var has_clans := false                  # the server has clans ("me" said so)
var clan: Dictionary = {}               # {} or {"id", "name", "tag", "house", "join", "min_lv", "n", "max", "lead", "role", "members", "req"?}
var clan_inv: Array = []                # invites: clan summaries with "by" (who invited)
var clan_asked: Array = []              # clan ids this player asked to join
var clan_cool := 0                      # unix: no joining a clan before then (0: free)
var clan_cost := 10000
var clan_max := 30
var clan_list: Array = []               # the last search's clans
var clan_query := ""
var clan_infos := {}                    # clan id -> its card (clan_info), "_at": clock
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

func account_switched() -> void:
	# 0.31.132: this phone plays as another account now (a transfer code, Game Center, or a deleted account): the
	# connection starts again with it
	clan = {}
	clan_inv = []
	clan_asked = []
	clan_cool = 0
	lines.clan = []
	unread.clan = 0
	_close()
	_fails = 0
	_next_try = _clock

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
			me = {"pid":str(m.get("pid", "")), "n":str(m.get("n", "")), "tt":str(m.get("tt", "")), "max":int(m.get("max", 120)), "ct":str(m.get("ct", ""))}
			has_clans = int(m.get("clans", 0)) == 1
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
		"clan":                                       # 0.31.134: my clan (or none), my invites
			var c: Variant = m.get("clan", {})
			var was := str(clan.get("id", ""))
			clan = c if c is Dictionary else {}
			clan_inv = m.get("inv", []) if m.get("inv", []) is Array else []
			clan_asked = m.get("asked", []) if m.get("asked", []) is Array else []
			clan_cool = int(m.get("cool", 0))
			clan_cost = int(m.get("cost", clan_cost))
			clan_max = int(m.get("max", clan_max))
			me["ct"] = str(clan.get("tag", ""))
			if str(clan.get("id", "")) != was:
				lines.clan = []
				unread.clan = 0
			changed.emit("clan")
		"clans":
			clan_list = m.get("list", []) if m.get("list", []) is Array else []
			clan_query = str(m.get("q", ""))
			changed.emit("clans")
		"clan_info":
			var ci: Variant = m.get("c", {})
			var info: Dictionary = (ci as Dictionary).duplicate() if ci is Dictionary else {}
			info["_at"] = _clock
			clan_infos[str(m.get("id", ""))] = info
			changed.emit("clan_info")
		"clan_inv":
			clan_invited.emit(m.get("c", {}), m.get("by", {}))
		"clan_made":
			clan_made.emit(bool(m.get("ok", false)), str(m.get("why", "")))
		"prof":
			var pp := str(m.get("pid", ""))
			if pp != "":
				var pr := m.duplicate()
				pr["_at"] = _clock
				profiles[pp] = pr
				changed.emit("prof")

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

func ask_profile(pid: String) -> bool:
	# 0.31.120 (Kevin: player profile card): the numbers on a player's card; kept a minute
	var pr: Dictionary = profiles.get(pid, {})
	if not pr.is_empty() and str(pr.get("why", "")) != "busy" and _clock - float(pr.get("_at", -999.0)) < 60.0:
		return true
	return _send({"k":"prof", "pid":pid})

func profile_of(pid: String) -> Dictionary:
	return profiles.get(pid, {})

# ---------------- clans (0.31.134) ----------------
func clan_new(name: String, tag: String, house: String, join: String, min_lv: int) -> bool:
	return _send({"k":"clan_new", "name":name.strip_edges(), "tag":tag.strip_edges().to_upper(), "house":house, "join":join, "min_lv":min_lv})

func clan_find(q: String, house := "") -> bool:
	return _send({"k":"clan_find", "q":q.strip_edges(), "house":house})

func clan_info(id: String) -> bool:
	return _send({"k":"clan_info", "id":id})

func clan_join(id: String) -> bool:
	return _send({"k":"clan_join", "id":id})

func clan_unreq(id: String) -> bool:
	return _send({"k":"clan_unreq", "id":id})

func clan_noinv(id: String) -> bool:
	clan_inv = clan_inv.filter(func(c): return str(c.get("id", "")) != id)
	changed.emit("clan")
	return _send({"k":"clan_noinv", "id":id})

func clan_accept(pid: String) -> bool:
	return _send({"k":"clan_accept", "pid":pid})

func clan_reject(pid: String) -> bool:
	return _send({"k":"clan_reject", "pid":pid})

func clan_invite(pid: String) -> bool:
	return _send({"k":"clan_invite", "pid":pid.strip_edges().to_lower()})

func clan_leave() -> bool:
	return _send({"k":"clan_leave"})

func clan_kick(pid: String) -> bool:
	return _send({"k":"clan_kick", "pid":pid})

func clan_role(pid: String, role: String) -> bool:
	return _send({"k":"clan_role", "pid":pid, "role":role})

func clan_lead(pid: String) -> bool:
	return _send({"k":"clan_lead", "pid":pid})

func clan_set(join: String, min_lv: int) -> bool:
	return _send({"k":"clan_set", "join":join, "min_lv":min_lv})

func clan_disband() -> bool:
	return _send({"k":"clan_disband"})

func in_clan() -> bool:
	return not clan.is_empty()

func clan_role_of_me() -> String:
	return str(clan.get("role", ""))

func is_clan_officer() -> bool:
	return clan_role_of_me() in ["leader", "officer"]

func my_tag() -> String:
	return str(clan.get("tag", ""))

func clan_requests() -> int:
	return (clan.get("req", []) as Array).size()

func clan_cool_left() -> int:
	return maxi(0, clan_cool - int(Time.get_unix_time_from_system()))

static func tagged(name: String, ct: String) -> String:
	# "[WOLF] Kevin" -- a player's name with their clan tag before it
	return ("[%s] %s" % [ct, name]) if ct != "" else name

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

func in_my_clan(pid: String) -> bool:
	for c in clan.get("members", []):
		if str(c.pid) == pid:
			return true
	return false

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
	for l in [friends, rin, rout, blocked, party.get("members", []), clan.get("members", [])]:
		for c in l:
			if str(c.pid) == pid:
				return c
	return {}

func attention() -> int:
	# the Home badge: friend requests and party invites waiting (0.31.134: clan invites, and requests for officers)
	return rin.size() + invites.size() + clan_inv.size() + (clan_requests() if is_clan_officer() else 0)

func unread_total() -> int:
	return int(unread.global) + int(unread.party) + int(unread.clan)

static func code_of(pid: String) -> String:
	return pid.to_upper()
