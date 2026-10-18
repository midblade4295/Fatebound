extends RefCounted
# 0.31.111 (Kevin: "Build a global chat and players can click a name and have option to add friend to a friends list.
# They can then group up and form a party. Also add the quick chat pings"): the social side of the Siege server.
#
# A phone with an account (server/eco_accounts.gd) keeps one social WebSocket open while the app is up: the first
# message is {"t":"so", "k":"hi", "acct", "key"}; after that every message both ways is {"t":"so", "k":...}. Players
# know each other by a public id (pid: the first 10 hex of the SHA-256 of the account id -- never the account id, which
# with its key is a login). The pid, upper-cased, is the player's friend code.
#   chat     "global" (everyone online) and "party". 120 characters; a word filter and links masked; at most one every
#            1.2 s and 6 in 20 s, and not the same line twice running. The last 50 global lines (30 a party) are sent on
#            connect. Nothing from a player you blocked ever reaches you.
#   friends  "add" sends a request, or accepts theirs; "decline"; "unfriend" (also takes back a request). 100 friends.
#            Each friend is "online" (the app is up), "match" (in a match on this server) or "offline" (+ last seen).
#   block    their chat is hidden from you; they can't friend or invite you (a request to you looks sent to them but
#            never arrives); unfriends.
#   report   a line in reports.jsonl in the state directory: who, about whom, why, their last lines -- for the developer.
#   muted    pids listed in muted.txt in the state directory (one a line, # comments; re-read every 10 s) can't chat.
#   party    up to 4. A member invites a friend who is online and not in a match (the invite lasts 60 s); "join",
#            "nojoin", "leave", "kick" (the leader). The leader's "play" sends every member in the menu "go": their apps
#            join the online match with "party" in the hello, and siege_server seats a party on one team. A party is
#            gone when one member is left with no invite out; a member away from the app for 3 minutes leaves it.
# Kept in social.json in the state directory (names, friends, requests, blocks), written 3 s after a change.
# 0.31.140 (Kevin: "make it so the chat messages don't get deleted, only delete after 50 messages"): the global and
# clan chats are kept too, in chat.json beside it (written with it), so a server restart or update no longer empties
# them; each keeps its last 50 lines, the oldest going as a new one comes. (Party chat ends with its party.)
# 0.31.134 (Crown War step 1): clans (server/clans.gd, set as `clans` by siege_server.gd) ride this socket too: the
# "clan_*" messages go there, "clan" is a third chat channel (the clan's members), and cards and chat lines carry the
# player's clan tag ("ct"). "me" says "clans":1 when the server has them.
const CHAT_MAX := 120
const HIST_GLOBAL := 50
const HIST_PARTY := 30
const HIST_CLAN := 50      # 0.31.134 (server/clans.gd keeps the same number)
const CHAT_GAP := 1.2
const CHAT_BURST := 6
const CHAT_WINDOW := 20.0
const MAX_FRIENDS := 100
const MAX_REQ_OUT := 50
const MAX_REQ_IN := 100
const MAX_BLOCKED := 200
const PARTY_MAX := 4
const INVITE_LIFE := 60.0
const PARTY_GRACE := 180.0
const SAVE_DELAY := 3.0
const MUTE_RELOAD := 10.0
const MAX_CONN_PER_PLAYER := 2
const MAX_CONNS := 4000
const REPORTS_PER_HOUR := 10
const PROF_BURST := 12        # 0.31.120: profile cards a player may ask for in PROF_WINDOW seconds
const PROF_WINDOW := 10.0
const REPORT_REASONS := ["language", "spam", "cheating", "name", "other"]

var state := ""
var path := ""
var users := {}            # pid -> {"acct", "name", "title", "friends", "rin", "rout", "blocked", "seen"}
var by_acct := {}          # account id -> pid
var conns := {}            # socket id -> pid
var online := {}           # pid -> [socket ids]
var parties := {}          # party id -> {"id", "leader", "members"}
var party_of := {}         # pid -> party id
var invites := {}          # pid -> {party id: {"from": pid, "at": clock}}
var hist := {"global": []} # "global" / "p:<party id>" -> [line]
var rates := {}            # pid -> {"last", "times", "text"}
var reports := {}          # pid -> [clock] (the last hour)
var muted := {}
var away := {}             # pid -> clock when they left the app while in a party
var next_msg := 1
var chat_path := ""        # 0.31.140: chat.json, the global and clan chats
var next_party := 1
var clock := 0.0           # seconds, from tick()
var now_override := -1     # tests: the unix time
var eco = null             # eco_accounts.gd
var send_fn: Callable = func(_cid, _msg): pass
var close_fn: Callable = func(_cid): pass
var in_match_fn: Callable = func(_acct) -> bool: return false
var log_fn: Callable = func(_s): pass
var event_fn: Callable = func(_acct, _ev, _p): pass   # 0.31.118: usage statistics (server/analytics.gd) -- never the text
var rank_fn: Callable = func(_acct) -> int: return 0   # 0.31.120: this week's leaderboard rank (0: not on it)
var prof_at := {}          # 0.31.120: pid -> clocks of its recent profile-card asks
var clans = null           # 0.31.134: server/clans.gd (null: no clans -- the tests of this file alone)
var _dirty_at := -1.0
var _mute_clock := 0.0

func _init(state_dir := "", eco_ref = null) -> void:
	state = state_dir
	if state == "":
		state = OS.get_environment("STATE_DIRECTORY") if OS.has_environment("STATE_DIRECTORY") else "user://"
	path = state.path_join("social.json")
	chat_path = state.path_join("chat.json")
	eco = eco_ref
	_load()
	_load_chat()
	_reload_muted()

func friend_accts(acct: String) -> Array:
	# 0.31.119: the account ids of an account's friends (the leaderboard's friends tab)
	var out := []
	var pid: String = by_acct.get(acct, "")
	if pid == "" or not users.has(pid):
		return out
	for f in users[pid].get("friends", []):
		if users.has(f):
			out.append(str(users[f].acct))
	return out

static func pid_of(acct: String) -> String:
	return acct.sha256_text().left(10)

func unix() -> int:
	return now_override if now_override >= 0 else int(Time.get_unix_time_from_system())

# ---------------- the word filter ----------------
# Whole words (after undoing l33t spelling and stretched letters) and a few roots anywhere in a word; links masked.
# The list is deliberately short and blunt: add to it here.
const BAD_WORDS := ["fuck", "fucker", "fucking", "fuk", "fck", "motherfucker", "shit", "shitty", "bullshit", "bitch", "bitches",
	"cunt", "dick", "dickhead", "cock", "pussy", "asshole", "arsehole", "bastard", "whore", "slut", "fag", "faggot", "nigger",
	"nigga", "niggas", "retard", "retarded", "twat", "wank", "wanker", "kys", "rape", "raped", "rapist", "nazi", "porn", "penis",
	"vagina", "cum", "dildo", "tits", "boobs", "spic", "chink", "kike", "tranny", "dyke", "hitler", "jizz", "prick"]
const BAD_ROOTS := ["fuck", "nigg", "fagg", "cunt", "bitch", "whore", "slut", "shit", "retard"]
const LEET := {"0":"o", "1":"i", "3":"e", "4":"a", "5":"s", "7":"t", "@":"a", "$":"s", "!":"i", "|":"i", "+":"t"}

static func _norm(w: String) -> String:
	var out := ""
	for ch in w.to_lower():
		var c: String = LEET.get(ch, ch)
		if (c >= "a" and c <= "z"):
			out += c
	return out

static func _squash(w: String) -> String:
	# "fuuuck" -> "fuck"
	var out := ""
	for ch in w:
		if out == "" or out[out.length() - 1] != ch:
			out += ch
	return out

static func is_bad_word(w: String) -> bool:
	var n := _norm(w)
	if n.length() < 2:
		return false
	var sq := _squash(n)
	if BAD_WORDS.has(n) or BAD_WORDS.has(sq):
		return true
	for r in BAD_ROOTS:
		if n.contains(r) or sq.contains(r):
			return true
	return false

static func _is_link(w: String) -> bool:
	var l := w.to_lower()
	if l.begins_with("http") or l.begins_with("www.") or l.contains("://"):
		return true
	for tld in [".com", ".net", ".org", ".gg", ".io", ".xyz", ".ly", ".co", ".ru", ".me", ".tv", ".app", ".link"]:
		var i := l.find(tld)
		if i > 0 and (i + tld.length() == l.length() or l[i + tld.length()] == "/"):
			return true
	return false

static func clean_text(s: String, max_len := CHAT_MAX) -> String:
	# control characters out, spaces squeezed, at most max_len; bad words and links become stars
	var flat := ""
	for ch in s:
		var u := ch.unicode_at(0)
		if u < 32 or u == 127 or (u >= 0x200B and u <= 0x200F) or (u >= 0x202A and u <= 0x202E) or u == 0xFEFF:
			flat += " "
		else:
			flat += ch
	var words := flat.strip_edges().split(" ", false)
	var out := PackedStringArray()
	for w in words:
		if _is_link(w) or is_bad_word(w):
			out.append("*".repeat(clampi(w.length(), 3, 8)))
		else:
			out.append(w)
	return " ".join(out).left(max_len).strip_edges()

static func clean_name(s: String) -> String:
	var n := clean_text(s, 20)
	return n if n != "" else "Player"

# ---------------- storage ----------------
func _load() -> void:
	users = {}
	by_acct = {}
	if not FileAccess.file_exists(path):
		return
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (v is Dictionary) or not (v.get("users", null) is Dictionary):
		return
	for pid in v.users:
		var u: Variant = v.users[pid]
		if not (u is Dictionary) or str(u.get("acct", "")) == "":
			continue
		for k in ["friends", "rin", "rout", "blocked"]:
			if not (u.get(k, null) is Array):
				u[k] = []
		users[str(pid)] = u
		by_acct[str(u.acct)] = str(pid)

func save_now() -> void:
	_write(path, {"v":1, "users":users})
	var kept := {}
	for key in hist:
		if str(key) == "global" or str(key).begins_with("c:"):
			kept[key] = hist[key]
	_write(chat_path, {"v":1, "next":next_msg, "hist":kept})
	_dirty_at = -1.0

func _write(to: String, v: Dictionary) -> void:
	var tmp := to + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(v))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(to))

func _load_chat() -> void:
	# 0.31.140: the global and clan chats as they were (the last HIST_GLOBAL / HIST_CLAN lines of each)
	if chat_path == "" or not FileAccess.file_exists(chat_path):
		return
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(chat_path))
	if not (v is Dictionary) or not (v.get("hist", null) is Dictionary):
		return
	var top := 0
	for key in v.hist:
		var k := str(key)
		if not (k == "global" or k.begins_with("c:")) or not (v.hist[key] is Array):
			continue
		var l: Array = (v.hist[key] as Array).filter(func(m): return m is Dictionary and str(m.get("x", "")) != "")
		for m in l:
			m["id"] = int(m.get("id", 0))                  # (JSON gives numbers back as floats)
			m["at"] = int(m.get("at", 0))
			top = maxi(top, int(m.id))
		hist[k] = l.slice(maxi(0, l.size() - (HIST_GLOBAL if k == "global" else HIST_CLAN)))
	next_msg = maxi(next_msg, maxi(int(v.get("next", 1)), top + 1))

func _mark() -> void:
	if _dirty_at < 0.0:
		_dirty_at = clock

func _reload_muted() -> void:
	var mp := state.path_join("muted.txt")
	var m := {}
	if FileAccess.file_exists(mp):
		for line in FileAccess.get_file_as_string(mp).split("\n"):
			var t := line.split("#")[0].strip_edges().to_lower()
			if t != "":
				m[t] = true
	muted = m

func tick(delta: float) -> void:
	clock += delta
	if _dirty_at >= 0.0 and clock - _dirty_at >= SAVE_DELAY:
		save_now()
	_mute_clock += delta
	if _mute_clock >= MUTE_RELOAD:
		_mute_clock = 0.0
		_reload_muted()
	if clans != null:
		clans.tick(delta)
	for pid in invites.keys():
		var mine: Dictionary = invites[pid]
		for pa in mine.keys():
			if mine.has(pa) and clock - float(mine[pa].at) > INVITE_LIFE:
				mine.erase(pa)
				_tidy(pa)
				if parties.has(pa):
					_send_party(pa)
		if mine.is_empty():
			invites.erase(pid)
	for pid in away.keys():
		if clock - float(away[pid]) > PARTY_GRACE:
			away.erase(pid)
			if party_of.has(pid) and not online.has(pid) and status_of(pid) != "match":
				_leave(pid)

# ---------------- connections ----------------
func status_of(pid: String) -> String:
	var u: Dictionary = users.get(pid, {})
	if u.is_empty():
		return "offline"
	if bool(in_match_fn.call(str(u.acct))):
		return "match"
	return "online" if online.has(pid) else "offline"

func _send(pid: String, msg: Dictionary) -> void:
	for cid in online.get(pid, []):
		send_fn.call(cid, msg)

func _note(pid: String, text: String, bad := false) -> void:
	_send(pid, {"t":"so", "k":"note", "x":text, "bad":bad})

func hello(cid: int, msg: Dictionary) -> bool:
	# {"k":"hi", "acct", "key"}: the player's account opens their social side
	if eco == null or conns.size() >= MAX_CONNS:
		send_fn.call(cid, {"t":"so", "k":"bye", "why":"busy"})
		return false
	var acct := str(msg.get("acct", ""))
	var e: Dictionary = eco.open(acct, str(msg.get("key", "")))
	if e.is_empty():
		send_fn.call(cid, {"t":"so", "k":"bye", "why":"auth"})
		return false
	var pid := pid_of(acct)
	var u: Dictionary = users.get(pid, {})
	if u.is_empty():
		u = {"acct":acct, "friends":[], "rin":[], "rout":[], "blocked":[]}
		users[pid] = u
		by_acct[acct] = pid
	_read_name(pid)
	u.seen = unix()
	_mark()
	var list: Array = online.get(pid, [])
	while list.size() >= MAX_CONN_PER_PLAYER:            # a newer socket for the same player: the oldest goes
		var old: int = list.pop_front()
		conns.erase(old)
		close_fn.call(old)
	list.append(cid)
	online[pid] = list
	conns[cid] = pid
	away.erase(pid)
	send_fn.call(cid, _me_msg(pid))
	send_fn.call(cid, _friends_msg(pid))
	send_fn.call(cid, {"t":"so", "k":"hist", "ch":"global", "list":_visible(pid, hist.global)})
	var pa: String = party_of.get(pid, "")
	send_fn.call(cid, _party_msg(pa))
	if pa != "":
		send_fn.call(cid, {"t":"so", "k":"hist", "ch":"party", "list":_visible(pid, hist.get("p:" + pa, []))})
	for ipa in invites.get(pid, {}):
		if parties.has(ipa):
			send_fn.call(cid, {"t":"so", "k":"inv", "party":ipa, "from":_card(str(invites[pid][ipa].from))})
	if clans != null:
		for m in clans.hello(pid):                       # 0.31.134: their clan and its chat
			send_fn.call(cid, m)
	if list.size() == 1:
		_presence(pid)
	return true

func drop(cid: int) -> void:
	var pid: String = conns.get(cid, "")
	if pid == "":
		return
	conns.erase(cid)
	var list: Array = online.get(pid, [])
	list.erase(cid)
	if not list.is_empty():
		return
	online.erase(pid)
	if users.has(pid):
		users[pid].seen = unix()
		_mark()
	if party_of.has(pid) and status_of(pid) != "match":
		away[pid] = clock
	_presence(pid)

func acct_changed(acct: String) -> void:
	# siege_server: a match socket with this account came or went
	var pid: String = by_acct.get(acct, "")
	if pid == "":
		return
	if status_of(pid) == "offline" and party_of.has(pid):
		away[pid] = clock
	else:
		away.erase(pid)
	_presence(pid)

func forget(acct: String) -> void:
	# 0.31.132: the account was deleted from the app -- its name, friends, requests and blocks go, and it leaves every
	# other player's lists; its sockets close. (Reports about it stay in reports.jsonl for the developer.)
	var pid: String = by_acct.get(acct, "")
	if pid == "":
		return
	if party_of.has(pid):
		_leave(pid)
	if clans != null:
		clans.forget(pid)
	for cid in conns.keys():
		if str(conns[cid]) == pid:
			close_fn.call(cid)
			conns.erase(cid)
	online.erase(pid)
	by_acct.erase(acct)
	users.erase(pid)
	for other in users:
		for k in ["friends", "rin", "rout", "blocked"]:
			(users[other][k] as Array).erase(pid)
	invites.erase(pid)
	rates.erase(pid)
	away.erase(pid)
	prof_at.erase(pid)
	_mark()
	log_fn.call("social: %s forgotten (account deleted)" % pid)

func party_for(acct: String) -> String:
	return party_of.get(by_acct.get(acct, ""), "")

func _read_name(pid: String) -> void:
	var u: Dictionary = users[pid]
	var pub: Dictionary = eco.public_of(str(u.acct)) if eco != null and eco.has_method("public_of") else {}
	u.name = clean_name(str(pub.get("name", u.get("name", "Player"))))
	u.title = str(pub.get("title", u.get("title", "")))

func _card(pid: String) -> Dictionary:
	var u: Dictionary = users.get(pid, {})
	var c := {"pid":pid, "n":str(u.get("name", "Player")), "tt":str(u.get("title", "")), "st":status_of(pid), "seen":int(u.get("seen", 0))}
	var ct := tag_of(pid)
	if ct != "":
		c["ct"] = ct                                     # 0.31.134: their clan's tag
	return c

func tag_of(pid: String) -> String:
	return clans.tag_of(pid) if clans != null else ""

func _me_msg(pid: String) -> Dictionary:
	var u: Dictionary = users[pid]
	var m := {"t":"so", "k":"me", "pid":pid, "n":str(u.name), "tt":str(u.get("title", "")), "max":CHAT_MAX}
	if clans != null:
		m["clans"] = 1
		m["ct"] = tag_of(pid)
	return m

func _friends_msg(pid: String) -> Dictionary:
	var u: Dictionary = users[pid]
	var out := {"t":"so", "k":"friends"}
	for k in ["friends", "rin", "rout", "blocked"]:
		var l := []
		for o in u[k]:
			if users.has(str(o)):
				l.append(_card(str(o)))
		out[k] = l
	return out

func _presence(pid: String) -> void:
	# friends see them come and go; their party sees it too
	var u: Dictionary = users.get(pid, {})
	if u.is_empty():
		return
	var msg := {"t":"so", "k":"pres", "c":_card(pid)}
	for f in u.friends:
		_send(str(f), msg)
	var pa: String = party_of.get(pid, "")
	if pa != "":
		_send_party(pa)

func _visible(viewer: String, lines: Array) -> Array:
	var blocked: Array = users.get(viewer, {}).get("blocked", [])
	if blocked.is_empty():
		return lines
	return lines.filter(func(m): return not blocked.has(str(m.get("pid", ""))))

# ---------------- messages ----------------
func handle(cid: int, msg: Dictionary) -> void:
	var pid: String = conns.get(cid, "")
	if pid == "" or not users.has(pid):
		return
	var who := str(msg.get("pid", "")).to_lower().strip_edges()
	var k := str(msg.get("k", ""))
	if k.begins_with("clan_"):
		if clans != null:
			clans.handle(pid, msg)                       # 0.31.134
		return
	match k:
		"chat": _chat(pid, msg)
		"add": _add(pid, who)
		"decline": _decline(pid, who)
		"unfriend": _unfriend(pid, who)
		"block": _block(pid, who)
		"unblock": _unblock(pid, who)
		"report": _report(pid, who, str(msg.get("why", "other")))
		"invite": _invite(pid, who)
		"join": _join(pid, str(msg.get("party", "")))
		"nojoin": _decline_invite(pid, str(msg.get("party", "")))
		"leave": _leave(pid)
		"kick": _kick(pid, who)
		"play": _play(pid)
		"prof": _prof(cid, pid, who)
		"refresh":
			_read_name(pid)
			_mark()
			send_fn.call(cid, _me_msg(pid))
			send_fn.call(cid, _friends_msg(pid))
			_presence(pid)

func _prof(cid: int, pid: String, who: String) -> void:
	# 0.31.120 (Kevin: player profile card): someone tapped a name -- its card's numbers (eco_accounts.stats_of), to that
	# socket only. Not for a player who blocked the asker; at most PROF_BURST in PROF_WINDOW seconds ("busy" after that).
	var times: Array = (prof_at.get(pid, []) as Array).filter(func(t): return clock - float(t) < PROF_WINDOW)
	var out := {"t":"so", "k":"prof", "pid":who, "ok":false}
	if times.size() >= PROF_BURST:
		prof_at[pid] = times
		out["why"] = "busy"
		send_fn.call(cid, out)
		return
	times.append(clock)
	prof_at[pid] = times
	var u: Dictionary = users.get(who, {})
	if not u.is_empty() and not (u.get("blocked", []) as Array).has(pid) and eco != null and eco.has_method("stats_of"):
		var s: Dictionary = eco.stats_of(str(u.acct))
		if not s.is_empty():
			out.merge(s)
			out.ok = true
			out.n = str(u.get("name", "Player"))
			out.tt = str(u.get("title", ""))
			out.ct = tag_of(who)                          # 0.31.134: their clan's tag
			out.rank = int(rank_fn.call(str(u.acct)))
	send_fn.call(cid, out)

func _chat(pid: String, msg: Dictionary) -> void:
	var ch := str(msg.get("ch", "global"))
	if not ch in ["global", "party", "clan"]:
		return
	if muted.has(pid):
		_note(pid, "You can't chat right now", true)
		return
	var text := clean_text(str(msg.get("x", "")).left(CHAT_MAX * 4))
	if text == "":
		return
	var r: Dictionary = rates.get(pid, {"last":-99.0, "times":[], "text":""})
	if clock - float(r.last) < CHAT_GAP:
		_note(pid, "Slow down a little", true)
		return
	r.times = (r.times as Array).filter(func(t): return clock - float(t) < CHAT_WINDOW)
	if (r.times as Array).size() >= CHAT_BURST:
		_note(pid, "Slow down -- try again in a few seconds", true)
		return
	if text.to_lower() == str(r.text) and clock - float(r.last) < CHAT_WINDOW:
		_note(pid, "You just said that", true)
		return
	var pa: String = party_of.get(pid, "")
	if ch == "party" and pa == "":
		_note(pid, "You're not in a party", true)
		return
	var clan := str(clans.clan_of(pid)) if clans != null else ""
	if ch == "clan" and clan == "":
		_note(pid, "You're not in a clan", true)
		return
	r.last = clock
	(r.times as Array).append(clock)
	r.text = text.to_lower()
	rates[pid] = r
	var u: Dictionary = users[pid]
	event_fn.call(str(u.get("acct", "")), "chat_send", {"kind":ch})
	var m := {"id":next_msg, "ch":ch, "pid":pid, "n":str(u.name), "tt":str(u.get("title", "")), "x":text, "at":unix()}
	var ct := tag_of(pid)
	if ct != "":
		m["ct"] = ct
	next_msg += 1
	if ch == "clan":
		_hist_add("c:" + clan, m, HIST_CLAN)
		for mp in clans.members_of(clan):
			if not (users.get(str(mp), {}).get("blocked", []) as Array).has(pid):
				_send(str(mp), {"t":"so", "k":"chat", "m":m})
	elif ch == "global":
		_hist_add("global", m, HIST_GLOBAL)
		var out := {"t":"so", "k":"chat", "m":m}
		for other in online:
			if not (users.get(other, {}).get("blocked", []) as Array).has(pid):
				_send(str(other), out)
	else:
		_hist_add("p:" + pa, m, HIST_PARTY)
		for mp in parties[pa].members:
			if not (users.get(mp, {}).get("blocked", []) as Array).has(pid):
				_send(str(mp), {"t":"so", "k":"chat", "m":m})

func _hist_add(key: String, m: Dictionary, keep: int) -> void:
	var l: Array = hist.get(key, [])
	l.append(m)
	while l.size() > keep:
		l.pop_front()
	hist[key] = l
	if key == "global" or key.begins_with("c:"):
		_mark()                                        # (0.31.140: kept in chat.json)

func _sys(pa: String, text: String) -> void:
	# a line from the game itself in a party's chat ("Kevin joined the party")
	if not parties.has(pa):
		return
	var m := {"id":next_msg, "ch":"party", "sys":true, "x":text, "at":unix()}
	next_msg += 1
	_hist_add("p:" + pa, m, HIST_PARTY)
	for mp in parties[pa].members:
		_send(str(mp), {"t":"so", "k":"chat", "m":m})

# ---------------- friends ----------------
func _name(pid: String) -> String:
	return str(users.get(pid, {}).get("name", "Player"))

func _refresh(pid: String) -> void:
	if online.has(pid):
		_send(pid, _friends_msg(pid))

func _add(pid: String, target: String) -> void:
	# a request -- or, when they asked first, friends
	if target == pid:
		return
	if not users.has(target):
		_note(pid, "No player with that friend code", true)
		return
	var u: Dictionary = users[pid]
	var t: Dictionary = users[target]
	if (u.friends as Array).has(target):
		_note(pid, "You're already friends with %s" % _name(target))
		return
	if (u.blocked as Array).has(target):
		_note(pid, "Unblock %s first" % _name(target), true)
		return
	if (u.friends as Array).size() >= MAX_FRIENDS:
		_note(pid, "Your friends list is full (%d)" % MAX_FRIENDS, true)
		return
	if (u.rin as Array).has(target):
		if (t.friends as Array).size() >= MAX_FRIENDS:
			_note(pid, "%s's friends list is full" % _name(target), true)
			return
		u.rin.erase(target)
		t.rout.erase(pid)
		u.friends.append(target)
		t.friends.append(pid)
		event_fn.call(str(u.get("acct", "")), "friend_accept", {})
		_mark()
		_refresh(pid)
		_refresh(target)
		_note(pid, "You and %s are friends now" % _name(target))
		_send(target, {"t":"so", "k":"note", "x":"%s accepted your friend request" % _name(pid), "pop":true})
		return
	if (u.rout as Array).has(target):
		_note(pid, "Friend request already sent")
		return
	if (u.rout as Array).size() >= MAX_REQ_OUT:
		_note(pid, "Too many requests waiting for an answer", true)
		return
	u.rout.append(target)
	event_fn.call(str(u.get("acct", "")), "friend_add", {})
	if not (t.blocked as Array).has(pid):                 # (blocked: it looks sent, and never arrives)
		t.rin.append(pid)
		while (t.rin as Array).size() > MAX_REQ_IN:
			var old := str(t.rin.pop_front())
			if users.has(old):
				users[old].rout.erase(target)
		_send(target, {"t":"so", "k":"req", "from":_card(pid)})
		_refresh(target)
	_mark()
	_refresh(pid)
	_note(pid, "Friend request sent to %s" % _name(target))

func _decline(pid: String, target: String) -> void:
	if not users.has(target):
		return
	users[pid].rin.erase(target)
	users[target].rout.erase(pid)
	_mark()
	_refresh(pid)
	_refresh(target)

func _unfriend(pid: String, target: String) -> void:
	if not users.has(target):
		return
	var u: Dictionary = users[pid]
	var t: Dictionary = users[target]
	for k in ["friends", "rin", "rout"]:
		u[k].erase(target)
		t[k].erase(pid)
	_mark()
	_refresh(pid)
	_refresh(target)

func _block(pid: String, target: String) -> void:
	if target == pid or not users.has(target):
		return
	var u: Dictionary = users[pid]
	if not (u.blocked as Array).has(target):
		u.blocked.append(target)
		while (u.blocked as Array).size() > MAX_BLOCKED:
			u.blocked.pop_front()
	_unfriend(pid, target)
	if clans != null:
		clans.blocked(pid, target)                       # 0.31.134: their clan invites to you go too
	for pair in [[pid, target], [target, pid]]:            # no invites between them
		var mine: Dictionary = invites.get(pair[0], {})
		for pa in mine.keys():
			if mine.has(pa) and str(mine[pa].from) == pair[1]:
				mine.erase(pa)
				_tidy(pa)
				_send_party(pa)
	_note(pid, "%s is blocked. You won't see their messages." % _name(target))

func _unblock(pid: String, target: String) -> void:
	users[pid].blocked.erase(target)
	_mark()
	_refresh(pid)

func _report(pid: String, target: String, why: String) -> void:
	if target == pid or not users.has(target):
		return
	var mine: Array = (reports.get(pid, []) as Array).filter(func(t): return clock - float(t) < 3600.0)
	if mine.size() >= REPORTS_PER_HOUR:
		_note(pid, "You've sent a lot of reports -- try again later", true)
		return
	mine.append(clock)
	reports[pid] = mine
	var lines := []
	var pa: String = party_of.get(pid, "")
	var my_clan := str(clans.clan_of(pid)) if clans != null else ""
	for key in ["global", "p:" + pa, "c:" + my_clan]:
		for m in hist.get(key, []):
			if str(m.get("pid", "")) == target:
				lines.append(str(m.x))
	var rec := {"at":unix(), "by":pid, "by_name":_name(pid), "about":target, "about_name":_name(target),
		"about_acct":str(users[target].acct), "why":why if why in REPORT_REASONS else "other", "lines":lines.slice(maxi(0, lines.size() - 5))}
	var rp := state.path_join("reports.jsonl")
	var f := FileAccess.open(rp, FileAccess.READ_WRITE if FileAccess.file_exists(rp) else FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line(JSON.stringify(rec))
		f.close()
	log_fn.call("REPORT %s about %s (%s): %s" % [_name(pid), _name(target), rec.why, target])
	_note(pid, "Thanks -- your report was sent")

# ---------------- parties ----------------
func _pending(pa: String) -> Array:
	var out := []
	for pid in invites:
		if (invites[pid] as Dictionary).has(pa):
			out.append(pid)
	return out

func _party_msg(pa: String) -> Dictionary:
	if pa == "" or not parties.has(pa):
		return {"t":"so", "k":"party", "party":{}}
	var p: Dictionary = parties[pa]
	var mem := []
	for m in p.members:
		mem.append(_card(str(m)))
	var pend := []
	for m in _pending(pa):
		pend.append(_card(str(m)))
	return {"t":"so", "k":"party", "party":{"id":pa, "leader":str(p.leader), "members":mem, "pending":pend, "max":PARTY_MAX}}

func _send_party(pa: String) -> void:
	if not parties.has(pa):
		return
	var msg := _party_msg(pa)
	for m in parties[pa].members:
		_send(str(m), msg)

func _new_party(pid: String) -> String:
	var pa := "%d%s" % [next_party, Crypto.new().generate_random_bytes(3).hex_encode()]
	next_party += 1
	parties[pa] = {"id":pa, "leader":pid, "members":[pid]}
	party_of[pid] = pa
	return pa

func _tidy(pa: String) -> void:
	# one member and nobody invited: no party
	if not parties.has(pa):
		return
	var p: Dictionary = parties[pa]
	var n := (p.members as Array).size()
	if n > 1 or (n == 1 and not _pending(pa).is_empty()):
		return
	for m in p.members:
		party_of.erase(str(m))
		away.erase(str(m))
		_send(str(m), _party_msg(""))
	for pid in invites:
		(invites[pid] as Dictionary).erase(pa)
	parties.erase(pa)
	hist.erase("p:" + pa)

func _invite(pid: String, target: String) -> void:
	if not users.has(target) or target == pid:
		return
	if not (users[pid].friends as Array).has(target):
		_note(pid, "You can only invite friends", true)
		return
	var st := status_of(target)
	if st == "offline":
		_note(pid, "%s isn't online" % _name(target), true)
		return
	if st == "match":
		_note(pid, "%s is in a match right now" % _name(target), true)
		return
	var pa: String = party_of.get(pid, "")
	if pa != "" and (parties[pa].members as Array).has(target):
		_note(pid, "%s is already in your party" % _name(target))
		return
	if pa != "" and (parties[pa].members as Array).size() + _pending(pa).size() >= PARTY_MAX:
		_note(pid, "Your party is full (%d)" % PARTY_MAX, true)
		return
	if pa == "":
		pa = _new_party(pid)
		event_fn.call(str(users[pid].get("acct", "")), "party_create", {})
	var mine: Dictionary = invites.get(target, {})
	mine[pa] = {"from":pid, "at":clock}
	invites[target] = mine
	_send(target, {"t":"so", "k":"inv", "party":pa, "from":_card(pid)})
	event_fn.call(str(users[pid].get("acct", "")), "party_invite", {})
	_send_party(pa)
	_note(pid, "Invited %s to your party" % _name(target))

func _join(pid: String, pa: String) -> void:
	var mine: Dictionary = invites.get(pid, {})
	if not mine.has(pa) or not parties.has(pa):
		_note(pid, "That invite has run out", true)
		_send(pid, _party_msg(party_of.get(pid, "")))
		return
	mine.erase(pa)
	if (parties[pa].members as Array).size() >= PARTY_MAX:
		_note(pid, "That party is full", true)
		return
	if party_of.has(pid):
		if party_of[pid] == pa:
			return
		_leave(pid)
	if not parties.has(pa):                               # (leaving our old party can't end this one, but be safe)
		_note(pid, "That party is gone", true)
		return
	parties[pa].members.append(pid)
	party_of[pid] = pa
	event_fn.call(str(users[pid].get("acct", "")), "party_join", {"n":(parties[pa].members as Array).size()})
	_sys(pa, "%s joined the party" % _name(pid))
	_send_party(pa)
	_send(pid, {"t":"so", "k":"hist", "ch":"party", "list":_visible(pid, hist.get("p:" + pa, []))})

func _decline_invite(pid: String, pa: String) -> void:
	var mine: Dictionary = invites.get(pid, {})
	if not mine.has(pa):
		return
	var from := str(mine[pa].from)
	mine.erase(pa)
	_note(from, "%s can't join right now" % _name(pid))
	_tidy(pa)
	_send_party(pa)

func _leave(pid: String) -> void:
	var pa: String = party_of.get(pid, "")
	if pa == "" or not parties.has(pa):
		party_of.erase(pid)
		return
	var p: Dictionary = parties[pa]
	party_of.erase(pid)
	away.erase(pid)
	p.members.erase(pid)
	_send(pid, _party_msg(""))
	if str(p.leader) == pid and not (p.members as Array).is_empty():
		p.leader = str(p.members[0])
	_sys(pa, "%s left the party" % _name(pid))
	for m in _pending(pa):                                # (their invites go with them)
		if str(invites[m][pa].from) == pid:
			invites[m][pa].from = str(p.leader)
	_tidy(pa)
	_send_party(pa)

func _kick(pid: String, target: String) -> void:
	var pa: String = party_of.get(pid, "")
	if pa == "" or str(parties[pa].leader) != pid or target == pid or party_of.get(target, "") != pa:
		return
	_leave(target)
	_note(target, "You were removed from the party", true)

func _play(pid: String) -> void:
	# the leader starts: everyone in the menu goes into the online match with them (0.31.169: Crown War's battles -- a
	# "war" id -- went with Crown War)
	var pa: String = party_of.get(pid, "")
	if pa == "" or str(parties[pa].leader) != pid:
		return
	var n := 0
	for m in parties[pa].members:
		if str(m) != pid and online.has(str(m)) and status_of(str(m)) == "online":
			_send(str(m), {"t":"so", "k":"go", "party":pa, "by":_name(pid)})
			n += 1
	_sys(pa, "%s is heading into battle%s" % [_name(pid), " -- the party follows!" if n > 0 else ""])
	log_fn.call("party %s plays (%d with the leader)" % [pa, n + 1])
