extends RefCounted
# 0.31.134 (Kevin, Crown War step 1 -- the "Crown War" design doc): clans. A clan belongs to one of the three houses
# (picked when it is made, never changed), has up to MAX_MEMBERS members (a leader, officers, members) and its own chat
# channel. It lives beside server/social.gd and speaks over the same social socket: every message is
# {"t":"so", "k":"clan_..."} (the phone's side is scripts/meta/social.gd).
#   clan_new   {name, tag, house, join, min_lv}   costs COST_GOLD from the account (eco_accounts.pay_gold), never gems;
#              the name (3-20 letters, digits, spaces, ' and -) and the tag (3-4 of A-Z 0-9) pass the chat's word filter
#              and are unique. -> {"k":"clan_made", "ok", "why"?} (the phone then pulls its account: the gold changed)
#   clan_find  {q, house?}  clans by name or tag (empty: the biggest)    -> {"k":"clans", "q", "list":[summary]}
#   clan_info  {id}         a clan's card and members                     -> {"k":"clan_info", "c":{summary + members}}
#   clan_join  {id}         "open": in (level >= min_lv); "request": a request the officers answer; "invite": only with
#                           an invite (an invite also lets a player past the level and the mode)
#   clan_unreq {id} / clan_noinv {id}         take back a request / turn down an invite
#   clan_accept {pid} / clan_reject {pid}     officers and the leader answer requests
#   clan_invite {pid}       officers and the leader invite a player (by friend code / name card)
#   clan_leave              a leader who leaves hands the clan on (an officer first, the one seen last); the last one
#                           out ends it
#   clan_kick {pid}         the leader removes anyone; an officer removes members
#   clan_role {pid, role}   the leader makes a member an officer ("officer") or an officer a member ("member")
#   clan_lead {pid}         the leader hands the clan to a member (and stays on as an officer)
#   clan_set {join, min_lv} the leader and officers
#   clan_disband            the leader ends the clan
# Whoever leaves or is removed waits COOLDOWN (24 h) before joining or making another clan. A leader not seen for
# LEADER_AWAY (14 days) hands the clan to the officer seen last (or, with no officer seen since, the member seen last).
# Each member's state comes as {"k":"clan", "clan":{...} or {}, "inv":[invites], "cool":unix} on hello and on every
# change; clan chat is social.gd's "clan" channel (history "c:<id>", kept like global's in chat.json since 0.31.140). The tag shows before
# names: social cards and chat lines carry "ct", the match's "pn" and lobby carry it per player (siege_server.gd), and
# leaderboard rows too.
# Kept in clans.json in the state directory (clans, invites, cooldowns), written SAVE_DELAY s after a change.
# 0.31.148 (Kevin: "Make it cost 5000 gold and make a default clan for each faction that the new players can choose since
# there are no clans in game yet"): COST_GOLD 5,000 (was 10,000); and a HOUSE CLAN for each house (HOUSE_CLANS), made
# when the server starts and never gone: free, open to all, level 1, up to HOUSE_CLAN_MAX members, no leader or officers
# (nobody runs it: no invites, requests, removals, settings or disbanding; never handed on), "hc" in its summary. Its
# members leave it without the 24-hour wait, a cooldown doesn't keep anyone out of it, and joining or starting a
# players' clan moves a member out of it by itself. Its card shows HOUSE_LIST_MAX members (online first), and its chat
# gets no join / leave lines.
# 0.31.196 (Kevin: "Now let's redo the clan system for new game" -> "Do clan chest, clan camp, crest, shard requests,
# 5-stack, lfg button, league"; the numbers are Eco's CLAN_* in scripts/meta/economy.gd):
#   - the CREST (an emblem, its colour, the shield's colour: Eco.CLAN_EMBLEMS / CLAN_CHARGES / CLAN_FIELDS) takes the
#     house's place: picked when a clan is made, changed by the leader and officers (clan_crest {e, f, c}). A clan made by
#     an older app with a house gets that house's crest (Eco.CLAN_HOUSE_CREST); the house clans have theirs. "house"
#     still goes out (older apps show it). Cards, chat lines, the match's names and the leaderboard carry "cc", the
#     crest's code (Eco.crest_code) beside "ct".
#   - CLAN POINTS: add_match (siege_server _pay_match, every paid online match) gives the member's players' clan
#     Eco.clan_points, doubled for one who had a clanmate in his party; they are the clan's XP (its LEVEL: Eco.CLAN_LEVELS,
#     which grows the camp) and its WEEK's points (Monday 00:00 UTC, as the leaderboard) -- who earned what ("by").
#   - When a week ends (_roll), each players' clan that earned points is paid: its CLAN CHEST (the tier reached,
#     Eco.CLAN_CHEST_TIERS) and its CLAN LEAGUE place's gems (Eco.CLAN_LEAGUE_PRIZES) to every member who earned
#     Eco.CLAN_CHEST_MIN that week (eco_accounts.grant_clan_reward: once a week per account); the top three wear a gold,
#     silver or bronze frame round their crest for the week after ("fr"). clan_league answers the table.
#   - SHARD REQUESTS: clan_ask {h} (a hero the asker hasn't got, one ask open, at most one every Eco.CLAN_ASK_GAP, open
#     Eco.CLAN_ASK_LIFE), clan_unask, clan_give {pid}: a member holding a shard of that hero gives it
#     (eco_accounts.give_shard: the asker gets it, the giver its melt gold) and the clan Eco.CLAN_GIVE_XP; both phones are
#     told to fetch their accounts ({"k":"eco"}). The ask is a line in clan chat ("ask": the hero) too.
#   - LFG (server/social.gd "lfg" / "lfg_join"): a member's open call for his party, shown in clan chat and here ("lfg").
#   - The house clans (starter clans: free, open, nobody leads them) earn no points, chest or League place.
# A clan's state carries "cv": 2 (the phone shows the new parts only then).
const Eco = preload("res://scripts/meta/economy.gd")
const Leaderboard = preload("res://server/leaderboard.gd")   # (its week_of / week_end: the same weeks)
const CLAN_VERSION := 2
const LEAGUE_TOP := 50                 # clans in the League table
const HOUSES := ["lions", "stags", "ravens"]
const HOUSE_NAMES := {"lions": "Lions", "stags": "Stags", "ravens": "Ravens"}
const JOIN_MODES := ["open", "request", "invite"]
const MAX_MEMBERS := 30
const COST_GOLD := 5000             # 0.31.148 (Kevin): was 10,000
const NAME_MIN := 3
const NAME_MAX := 20
const TAG_MIN := 3
const TAG_MAX := 4
const MIN_LV_MAX := 100
const COOLDOWN := 24 * 3600
const LEADER_AWAY := 14 * 86400
const INVITE_LIFE := 7 * 86400
const REQ_LIFE := 7 * 86400
const MAX_INVITES := 20            # invites one player holds (the oldest goes)
const MAX_REQUESTS := 50           # requests one clan holds (the oldest goes)
const FIND_MAX := 20
const HIST_CLAN := 50
const SAVE_DELAY := 3.0
const CHECK_EVERY := 600.0         # s between the inactive-leader and expiry sweeps
const ROLES := ["leader", "officer", "member"]
const MSG_BURST := 20              # clan_* messages one player may send in MSG_WINDOW s (beyond: "slow down")
const MSG_WINDOW := 10.0
const ASK_POP_GAP := 3600          # s before the same player's request to the same clan pops up for its officers again
# 0.31.148: the house clans -- id, name, and the tags to try in turn (a players' clan may hold one already)
const HOUSE_CLANS := {
	"lions": {"id":"h_lions", "name":"The Lion Guard", "tags":["LION", "LNG", "LEO", "PRDE"]},
	"stags": {"id":"h_stags", "name":"The Stag Guard", "tags":["STAG", "STG", "HART", "ANTL"]},
	"ravens": {"id":"h_ravens", "name":"The Raven Guard", "tags":["RAVN", "RVG", "CROW", "WING"]},
}
const HOUSE_CLAN_MAX := 1000
const HOUSE_LIST_MAX := 40         # members on a house clan's card (online first, then the ones seen last)

var soc                            # server/social.gd (users, sockets, notes, the clock)
var path := ""
var clans := {}                    # id -> {"id", "name", "tag", "house", "join", "min_lv", "leader", "officers", "members", "req", "created"}
var member_of := {}                # pid -> clan id (rebuilt from clans)
var invites := {}                  # pid -> {clan id: {"by": pid, "at": unix}}
var cool := {}                     # pid -> unix: no joining before then
var _dirty_at := -1.0
var _check := 0.0
var _rate := {}                    # pid -> [clock] of its recent clan_* messages
var _asked_pop := {}               # "clan id:pid" -> unix of the last "asked to join" pop-up (memory only)
# 0.31.196
var week := ""                     # the week the clans' points are for (Leaderboard.week_of)
var asked_at := {}                 # pid -> unix of their last shard request (Eco.CLAN_ASK_GAP)
var league_last := []              # last week's top three clans: [{"name", "tag", "cr", "pts"}]
var _week_check := 0.0
var _push := {}                    # clan id -> true: its members' state goes out at the next push (points come often)
var _push_clock := 0.0
const PUSH_EVERY := 2.0

func _init(state_dir: String, social) -> void:
	soc = social
	path = state_dir.path_join("clans.json")
	_load()
	ensure_house_clans()

func unix() -> int:
	return soc.unix()

# ---------------- storage ----------------
func _load() -> void:
	clans = {}
	member_of = {}
	invites = {}
	cool = {}
	if not FileAccess.file_exists(path):
		return
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (v is Dictionary):
		return
	var cs: Variant = v.get("clans", {})
	if cs is Dictionary:
		for id in cs:
			var c: Variant = cs[id]
			if not (c is Dictionary) or not (c.get("members", null) is Dictionary) \
					or ((c.members as Dictionary).is_empty() and not bool(c.get("hc", false))):
				continue
			if not (c.get("officers", null) is Array):
				c["officers"] = []
			if not (c.get("req", null) is Dictionary):
				c["req"] = {}
			c["id"] = str(id)
			_fix(c)
			clans[str(id)] = c
			for pid in c.members:
				member_of[str(pid)] = str(id)
	var iv: Variant = v.get("inv", {})
	if iv is Dictionary:
		for pid in iv:
			if iv[pid] is Dictionary:
				invites[str(pid)] = iv[pid]
	var cl: Variant = v.get("cool", {})
	if cl is Dictionary:
		for pid in cl:
			cool[str(pid)] = int(cl[pid])
	week = str(v.get("week", ""))
	var aa: Variant = v.get("asked", {})
	if aa is Dictionary:
		for pid in aa:
			asked_at[str(pid)] = int(aa[pid])
	league_last = v.get("league_last", []) if v.get("league_last", []) is Array else []

func _fix(c: Dictionary) -> void:
	# 0.31.196: a clan from an older file -- its crest (its house's), XP, the week's points, frame, shard requests
	if Eco.clean_crest(c.get("crest", null)).is_empty():
		c["crest"] = (Eco.CLAN_HOUSE_CREST.get(str(c.get("house", "")), {"e":3, "f":0, "c":0}) as Dictionary).duplicate()
	else:
		c["crest"] = Eco.clean_crest(c.crest)
	c["xp"] = int(c.get("xp", 0))
	var wk: Variant = c.get("wk", null)
	if not (wk is Dictionary) or not (wk.get("by", null) is Dictionary):
		c["wk"] = {"week":"", "pts":0, "by":{}}
	else:
		wk["pts"] = int(wk.get("pts", 0))
		wk["week"] = str(wk.get("week", ""))
		for pid in (wk.by as Dictionary).keys():
			wk.by[pid] = int(wk.by[pid])
	c["fr"] = str(c.get("fr", ""))
	if not (c.get("ask", null) is Dictionary):
		c["ask"] = {}
	if not (c.get("last", null) is Dictionary):
		c["last"] = {}

func ensure_house_clans() -> void:
	# 0.31.148: each house's clan, made if it's missing (and kept as one: open, level 1, nobody leading it)
	for h in HOUSES:
		var spec: Dictionary = HOUSE_CLANS[h]
		var id := str(spec.id)
		if clans.has(id):
			var c: Dictionary = clans[id]
			c["hc"] = true
			c["house"] = h
			c["join"] = "open"
			c["min_lv"] = 1
			c["leader"] = ""
			c["officers"] = []
			c["req"] = {}
			c["crest"] = (Eco.CLAN_HOUSE_CREST[h] as Dictionary).duplicate()
			_fix(c)
			continue
		var tag := ""
		for t in spec.tags:
			if not clans.values().any(func(o): return str(o.tag) == str(t)):
				tag = str(t)
				break
		if tag == "":
			tag = h.left(3).to_upper() + "0"
		clans[id] = {"id":id, "name":str(spec.name), "tag":tag, "house":h, "join":"open", "min_lv":1, "leader":"",
			"officers":[], "members":{}, "req":{}, "created":unix(), "hc":true, "crest":(Eco.CLAN_HOUSE_CREST[h] as Dictionary).duplicate()}
		_fix(clans[id])
		soc.log_fn.call("clan %s [%s] %s: House %s's clan" % [id, tag, str(spec.name), HOUSE_NAMES[h]])
		_mark()

func is_house(id: String) -> bool:
	return clans.has(id) and bool(clans[id].get("hc", false))

func max_of(c: Dictionary) -> int:
	return HOUSE_CLAN_MAX if bool(c.get("hc", false)) else MAX_MEMBERS

func _out_of_house(pid: String) -> void:
	# joining or starting a players' clan (or another house's clan): out of the house clan first, no wait, no line
	var id: String = member_of.get(pid, "")
	if id != "" and is_house(id):
		_remove(id, pid)

func save_now() -> void:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"v":2, "clans":clans, "inv":invites, "cool":cool, "week":week, "asked":asked_at,
		"league_last":league_last}))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
	_dirty_at = -1.0

func _mark() -> void:
	if _dirty_at < 0.0:
		_dirty_at = soc.clock

func tick(delta: float) -> void:
	if _dirty_at >= 0.0 and soc.clock - _dirty_at >= SAVE_DELAY:
		save_now()
	_check += delta
	if _check >= CHECK_EVERY:
		_check = 0.0
		sweep()
	_week_check += delta
	if _week_check >= 60.0:
		_week_check = 0.0
		_roll()                                   # (a week ends on time even with nobody playing)
	_push_clock += delta
	if _push_clock >= PUSH_EVERY and not _push.is_empty():
		_push_clock = 0.0
		var ids := _push.keys()
		_push.clear()
		for id in ids:
			_refresh_all(str(id))

func sweep() -> void:
	# expired invites, requests and cooldowns; leaders away too long hand the clan on
	var t := unix()
	for pid in invites.keys():
		var mine: Dictionary = invites[pid]
		for id in mine.keys():
			if not clans.has(id) or t - int(mine[id].get("at", 0)) > INVITE_LIFE:
				mine.erase(id)
				_mark()
		if mine.is_empty():
			invites.erase(pid)
	for pid in cool.keys():
		if int(cool[pid]) <= t:
			cool.erase(pid)
			_mark()
	for id in clans.keys():
		var c: Dictionary = clans[id]
		for pid in (c.req as Dictionary).keys():
			if t - int(c.req[pid]) > REQ_LIFE:
				c.req.erase(pid)
				_mark()
		for pid in (c.ask as Dictionary).keys():          # 0.31.196: shard requests run out
			if t - int(c.ask[pid].get("at", 0)) > Eco.CLAN_ASK_LIFE or not (c.members as Dictionary).has(pid):
				c.ask.erase(pid)
				_mark()
		if not bool(c.get("hc", false)) and t - _seen(str(c.leader)) > LEADER_AWAY:
			var next := _successor(c, str(c.leader), true)
			if next != "":
				var old := str(c.leader)
				c.leader = next
				(c.officers as Array).erase(next)
				if not (c.officers as Array).has(old):
					(c.officers as Array).append(old)
				_mark()
				_sys(id, "%s leads the clan now (the leader was away %d days)" % [_name(next), LEADER_AWAY / 86400])
				soc.log_fn.call("clan %s: leader %s away, %s leads" % [id, old, next])
				_refresh_all(id)

# ---------------- lookups (social.gd, siege_server.gd, leaderboard) ----------------
func clan_of(pid: String) -> String:
	return member_of.get(pid, "")

func tag_of(pid: String) -> String:
	var id: String = member_of.get(pid, "")
	return str(clans[id].tag) if id != "" and clans.has(id) else ""

func tag_of_acct(acct: String) -> String:
	return tag_of(soc.pid_of(acct)) if acct != "" else ""

func crest_of(pid: String) -> String:
	# 0.31.196: the crest's code ("e.f.c") of pid's clan ("" for none)
	var id: String = member_of.get(pid, "")
	return Eco.crest_code(clans[id].get("crest", {})) if id != "" and clans.has(id) else ""

func crest_of_acct(acct: String) -> String:
	return crest_of(soc.pid_of(acct)) if acct != "" else ""

func old_house(c: Dictionary) -> String:
	# what an older app (0.31.134-0.31.195) shows as the clan's house: its own, or one by its emblem
	if str(c.get("house", "")) in HOUSES:
		return str(c.house)
	var e := int(c.get("crest", {}).get("e", 0))
	return str(HOUSES[e]) if e < 3 else str(HOUSES[e % 3])

func level_of(c: Dictionary) -> int:
	return 1 if bool(c.get("hc", false)) else Eco.clan_level(int(c.get("xp", 0)))

func week_pts(c: Dictionary) -> int:
	return int(c.wk.pts) if str(c.wk.get("week", "")) == week else 0

func members_of(id: String) -> Array:
	return (clans[id].members as Dictionary).keys() if clans.has(id) else []

func role_of(pid: String) -> String:
	var id: String = member_of.get(pid, "")
	if id == "" or not clans.has(id):
		return ""
	var c: Dictionary = clans[id]
	if str(c.leader) == pid:
		return "leader"
	return "officer" if (c.officers as Array).has(pid) else "member"

func _is_officer(pid: String) -> bool:
	return role_of(pid) in ["leader", "officer"]

func _name(pid: String) -> String:
	return str(soc.users.get(pid, {}).get("name", "Player"))

func _seen(pid: String) -> int:
	# when a member was last around: now while the app is up or they're in a match
	if not soc.users.has(pid):
		return 0
	if soc.status_of(pid) != "offline":
		return unix()
	return int(soc.users[pid].get("seen", 0))

func _successor(c: Dictionary, leaving: String, recent_only := false) -> String:
	# the officer seen last, else the member seen last (recent_only: only someone seen within LEADER_AWAY)
	var t := unix()
	for pool in [c.officers, (c.members as Dictionary).keys()]:
		var best := ""
		var best_t := -1
		for pid in pool:
			var p := str(pid)
			if p == leaving or not (c.members as Dictionary).has(p):
				continue
			var s := _seen(p)
			if recent_only and t - s > LEADER_AWAY:
				continue
			if s > best_t:
				best = p
				best_t = s
		if best != "":
			return best
	return ""

func _level(pid: String) -> int:
	var eco = soc.eco
	var u: Dictionary = soc.users.get(pid, {})
	if eco == null or u.is_empty() or not eco.has_method("stats_of"):
		return 1
	return int(eco.stats_of(str(u.acct)).get("lv", 1))

# ---------------- what goes to the phones ----------------
func summary(c: Dictionary) -> Dictionary:
	var s := {"id":str(c.id), "name":str(c.name), "tag":str(c.tag), "house":old_house(c), "join":str(c.join),
		"min_lv":int(c.min_lv), "n":(c.members as Dictionary).size(), "max":max_of(c), "lead":_name(str(c.leader)),
		"cv":CLAN_VERSION, "cr":(c.crest as Dictionary).duplicate(), "cc":Eco.crest_code(c.crest), "lv":level_of(c),
		"pts":week_pts(c)}
	if str(c.get("fr", "")) != "":
		s["fr"] = str(c.fr)                              # last week's League podium: "gold" / "silver" / "bronze"
	if bool(c.get("hc", false)):
		s["hc"] = true
		s["lead"] = ""
	return s

func _member_card(c: Dictionary, pid: String, full: bool) -> Dictionary:
	var card: Dictionary = soc._card(pid) if full else {"pid":pid, "n":_name(pid), "tt":str(soc.users.get(pid, {}).get("title", ""))}
	card["role"] = "leader" if str(c.leader) == pid else ("officer" if (c.officers as Array).has(pid) else "member")
	card["joined"] = int(c.members[pid])
	card["ct"] = str(c.tag)
	card["cc"] = Eco.crest_code(c.crest)
	card["wp"] = int(c.wk.by.get(pid, 0)) if str(c.wk.get("week", "")) == week else 0   # 0.31.196: this week's clan points
	return card

func _members_list(c: Dictionary, full: bool, me := "") -> Array:
	var order := {"leader":0, "officer":1, "member":2}
	var out := []
	var pids: Array = (c.members as Dictionary).keys()
	if bool(c.get("hc", false)) and pids.size() > HOUSE_LIST_MAX:
		# a house clan's card: HOUSE_LIST_MAX of them, the online ones first, then those seen last (and you)
		pids.sort_custom(func(a, b): return _seen(str(a)) > _seen(str(b)))
		var keep := pids.slice(0, HOUSE_LIST_MAX)
		if me != "" and (c.members as Dictionary).has(me) and not keep.has(me):
			keep.append(me)
		pids = keep
	for pid in pids:
		if soc.users.has(str(pid)):
			out.append(_member_card(c, str(pid), full))
	out.sort_custom(func(a, b):
		var ra := int(order.get(str(a.role), 3))
		var rb := int(order.get(str(b.role), 3))
		return ra < rb if ra != rb else str(a.n).nocasecmp_to(str(b.n)) < 0)
	return out

func state_msg(pid: String) -> Dictionary:
	var out := {"t":"so", "k":"clan", "clan":{}, "inv":[], "cost":COST_GOLD, "max":MAX_MEMBERS, "hcs":house_summaries()}
	var id: String = member_of.get(pid, "")
	if id != "" and clans.has(id):
		var c: Dictionary = clans[id]
		var mine := summary(c)
		mine["members"] = _members_list(c, true, pid)
		mine["role"] = role_of(pid)
		mine["created"] = int(c.get("created", 0))
		# 0.31.196: the clan's XP, the week (its end, the Clan Chest's tiers reached), last week's result, the shard
		# requests and LFG calls open, and when this player may ask again
		mine["xp"] = int(c.get("xp", 0))
		mine["week"] = week
		mine["ends"] = Leaderboard.week_end(unix())
		mine["tier"] = Eco.clan_tier(week_pts(c))
		mine["mine_pts"] = int(c.wk.by.get(pid, 0)) if str(c.wk.get("week", "")) == week else 0
		if not (c.last as Dictionary).is_empty():
			mine["last"] = (c.last as Dictionary).duplicate()
		var asks := []
		for a in c.ask:
			asks.append({"pid":str(a), "n":_name(str(a)), "h":str(c.ask[a].h), "at":int(c.ask[a].at)})
		mine["asks"] = asks
		mine["ask_next"] = int(asked_at.get(pid, 0)) + Eco.CLAN_ASK_GAP
		mine["lfg"] = soc.lfg_of_clan(id) if soc.has_method("lfg_of_clan") else []
		if _is_officer(pid):
			var rq := []
			for r in c.req:
				if soc.users.has(str(r)):
					var card: Dictionary = soc._card(str(r))
					card["lv"] = _level(str(r))
					card["at"] = int(c.req[r])
					rq.append(card)
			mine["req"] = rq
		out.clan = mine
	else:
		for cid in invites.get(pid, {}):
			if clans.has(cid):
				var s := summary(clans[cid])
				s["by"] = _name(str(invites[pid][cid].get("by", "")))
				out.inv.append(s)
		var asked := []
		for cid in clans:
			if (clans[cid].req as Dictionary).has(pid):
				asked.append(str(cid))
		out["asked"] = asked
	if int(cool.get(pid, 0)) > unix():
		out["cool"] = int(cool[pid])
	return out

func house_summaries() -> Array:
	# 0.31.148: the three house clans (every clan state carries them: the CLAN window offers them first)
	var out := []
	for h in HOUSES:
		var id := str(HOUSE_CLANS[h].id)
		if clans.has(id):
			out.append(summary(clans[id]))
	return out

func _refresh(pid: String) -> void:
	if soc.online.has(pid):
		soc._send(pid, state_msg(pid))

func _refresh_all(id: String) -> void:
	for pid in members_of(id):
		_refresh(str(pid))

func hello(pid: String) -> Array:
	# social.gd's hello: the player's clan state and clan chat history
	var out := [state_msg(pid)]
	var id: String = member_of.get(pid, "")
	if id != "":
		out.append({"t":"so", "k":"hist", "ch":"clan", "list":soc._visible(pid, soc.hist.get("c:" + id, []))})
	return out

func _sys(id: String, text: String) -> void:
	# a line from the game itself in the clan's chat ("Kevin joined the clan")
	if not clans.has(id):
		return
	var m := {"id":soc.next_msg, "ch":"clan", "sys":true, "x":text, "at":unix()}
	soc.next_msg += 1
	soc._hist_add("c:" + id, m, HIST_CLAN)
	for pid in members_of(id):
		soc._send(str(pid), {"t":"so", "k":"chat", "m":m})

# ---------------- messages ----------------
func handle(pid: String, msg: Dictionary) -> void:
	var times: Array = (_rate.get(pid, []) as Array).filter(func(t): return soc.clock - float(t) < MSG_WINDOW)
	if times.size() >= MSG_BURST:
		_rate[pid] = times
		soc._note(pid, "Slow down -- try again in a few seconds", true)
		return
	times.append(soc.clock)
	_rate[pid] = times
	var who := str(msg.get("pid", "")).to_lower().strip_edges()
	var id := str(msg.get("id", ""))
	match str(msg.get("k", "")):
		"clan_new": _new(pid, msg)
		"clan_find": _find(pid, str(msg.get("q", "")), str(msg.get("house", "")))
		"clan_info": _info(pid, id)
		"clan_join": _join(pid, id)
		"clan_unreq": _unreq(pid, id)
		"clan_noinv": _noinv(pid, id)
		"clan_accept": _accept(pid, who)
		"clan_reject": _reject(pid, who)
		"clan_invite": _invite(pid, who)
		"clan_leave": _leave(pid)
		"clan_kick": _kick(pid, who)
		"clan_role": _role(pid, who, str(msg.get("role", "")))
		"clan_lead": _lead(pid, who)
		"clan_set": _settings(pid, msg)
		"clan_disband": _disband(pid)
		"clan_state": _refresh(pid)
		"clan_crest": _crest(pid, msg)                  # 0.31.196
		"clan_ask": _ask(pid, str(msg.get("h", "")))
		"clan_unask": _unask(pid)
		"clan_give": _give(pid, who)
		"clan_league": _league(pid)

static func clean_clan_name(s: String) -> String:
	# letters, digits, spaces, ' and - only; spaces squeezed ("" when anything else is in it)
	var out := ""
	for ch in s.strip_edges():
		var ok: bool = (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch in " '-"
		if not ok:
			return ""
		if ch == " " and out.ends_with(" "):
			continue
		out += ch
	return out

static func name_key(s: String) -> String:
	return s.to_lower().replace(" ", "").replace("'", "").replace("-", "")

static func clean_tag(s: String) -> String:
	var t := s.strip_edges().to_upper()
	for ch in t:
		if not ((ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9")):
			return ""
	return t

func _cool_left(pid: String) -> int:
	return maxi(0, int(cool.get(pid, 0)) - unix())

static func hours_text(secs: int) -> String:
	var h := int(ceil(secs / 3600.0))
	return "%d hour%s" % [h, "" if h == 1 else "s"]

func _made(pid: String, ok: bool, why: String, text: String) -> void:
	soc._send(pid, {"t":"so", "k":"clan_made", "ok":ok, "why":why})
	if text != "":
		soc._note(pid, text, not ok)

func _new(pid: String, msg: Dictionary) -> void:
	if member_of.has(pid) and not is_house(str(member_of[pid])):
		_made(pid, false, "in_clan", "Leave your clan first")
		return
	if _cool_left(pid) > 0:
		_made(pid, false, "cool", "You can start or join a clan again in %s" % hours_text(_cool_left(pid)))
		return
	var name := clean_clan_name(str(msg.get("name", "")).left(NAME_MAX * 2))
	if name.length() < NAME_MIN or name.length() > NAME_MAX:
		_made(pid, false, "name", "A clan name is %d-%d letters, numbers or spaces" % [NAME_MIN, NAME_MAX])
		return
	if soc.clean_text(name, NAME_MAX) != name or name_key(name).length() < NAME_MIN:
		_made(pid, false, "name", "That name isn't allowed")
		return
	var tag := clean_tag(str(msg.get("tag", "")))
	if tag.length() < TAG_MIN or tag.length() > TAG_MAX:
		_made(pid, false, "tag", "A tag is %d-%d letters or numbers" % [TAG_MIN, TAG_MAX])
		return
	if soc.is_bad_word(tag) or soc.clean_text(tag, TAG_MAX) != tag:
		_made(pid, false, "tag", "That tag isn't allowed")
		return
	# 0.31.196: a crest ("cr"); an older app sends a house, which brings that house's crest
	var house := str(msg.get("house", ""))
	var crest := Eco.clean_crest(msg.get("cr", null))
	if crest.is_empty() and house in HOUSES:
		crest = (Eco.CLAN_HOUSE_CREST[house] as Dictionary).duplicate()
	if crest.is_empty():
		_made(pid, false, "crest", "Pick a crest")
		return
	if not house in HOUSES:
		house = ""
	var join := str(msg.get("join", "open"))
	if not join in JOIN_MODES:
		join = "open"
	var min_lv := clampi(int(msg.get("min_lv", 1)), 1, MIN_LV_MAX)
	for cid in clans:
		if name_key(str(clans[cid].name)) == name_key(name):
			_made(pid, false, "taken", "There's a clan called that already")
			return
		if str(clans[cid].tag) == tag:
			_made(pid, false, "taken", "Another clan has the tag [%s]" % tag)
			return
	var eco = soc.eco
	var acct := str(soc.users[pid].acct)
	if eco == null or not eco.has_method("pay_gold") or not bool(eco.pay_gold(acct, COST_GOLD, "clan")):
		_made(pid, false, "gold", "Starting a clan costs %s gold" % _thousands(COST_GOLD))
		return
	_out_of_house(pid)                                 # (0.31.148: a house clan's member moves to theirs)
	var id := "c" + Crypto.new().generate_random_bytes(5).hex_encode()
	while clans.has(id):
		id = "c" + Crypto.new().generate_random_bytes(5).hex_encode()
	var t := unix()
	clans[id] = {"id":id, "name":name, "tag":tag, "house":house, "join":join, "min_lv":min_lv, "leader":pid,
		"officers":[], "members":{pid: t}, "req":{}, "created":t, "crest":crest}
	_fix(clans[id])
	member_of[pid] = id
	_drop_pending(pid)
	_mark()
	soc.event_fn.call(acct, "clan_create", {"crest":Eco.crest_code(crest), "join":join})
	soc.log_fn.call("clan %s [%s] %s made by %s (crest %s)" % [id, tag, name, pid, Eco.crest_code(crest)])
	save_now()                                         # (the gold is gone: the clan is on disk at once too)
	_made(pid, true, "", "")
	_sys(id, "%s founded %s" % [_name(pid), name])
	_refresh(pid)
	soc._send(pid, {"t":"so", "k":"hist", "ch":"clan", "list":soc.hist.get("c:" + id, [])})
	_presence_tag(pid)

static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out

func _drop_pending(pid: String) -> void:
	# in a clan now: their invites and requests elsewhere go
	invites.erase(pid)
	for cid in clans:
		if (clans[cid].req as Dictionary).has(pid):
			clans[cid].req.erase(pid)
			for o in members_of(cid):
				if _is_officer(str(o)):
					_refresh(str(o))

func _presence_tag(pid: String) -> void:
	# their tag changed: friends and party see the new cards
	soc._presence(pid)
	soc._refresh(pid)

func _find(pid: String, q: String, house: String) -> void:
	var qq := q.strip_edges().to_lower().left(NAME_MAX)
	var list := []
	for cid in clans:
		var c: Dictionary = clans[cid]
		if qq != "" and not (str(c.name).to_lower().contains(qq) or str(c.tag).to_lower() == qq):
			continue
		list.append(c)
	# 0.31.196: the busiest first -- this week's points, then members (no house filter any more: the houses are gone)
	list.sort_custom(func(a, b):
		var pa := week_pts(a)
		var pb := week_pts(b)
		if pa != pb:
			return pa > pb
		var na := (a.members as Dictionary).size()
		var nb := (b.members as Dictionary).size()
		return na > nb if na != nb else int(a.get("created", 0)) < int(b.get("created", 0)))
	var out := []
	for c in list.slice(0, FIND_MAX):
		var s := summary(c)
		if (c.req as Dictionary).has(pid):
			s["asked"] = true
		if invites.get(pid, {}).has(str(c.id)):
			s["invited"] = true
		out.append(s)
	soc._send(pid, {"t":"so", "k":"clans", "q":q.left(NAME_MAX), "house":house, "list":out})

func _info(pid: String, id: String) -> void:
	if not clans.has(id):
		soc._send(pid, {"t":"so", "k":"clan_info", "id":id, "c":{}})
		return
	var c: Dictionary = clans[id]
	var s := summary(c)
	s["members"] = _members_list(c, member_of.get(pid, "") == id)
	s["created"] = int(c.get("created", 0))
	if (c.req as Dictionary).has(pid):
		s["asked"] = true
	if invites.get(pid, {}).has(id):
		s["invited"] = true
	soc._send(pid, {"t":"so", "k":"clan_info", "id":id, "c":s})

func _join(pid: String, id: String) -> void:
	if not clans.has(id):
		soc._note(pid, "That clan is gone", true)
		_refresh(pid)
		return
	if member_of.get(pid, "") == id:
		soc._note(pid, "You're in that clan already")
		return
	if member_of.has(pid) and not is_house(str(member_of[pid])):
		soc._note(pid, "You're in a clan already", true)
		return
	var c: Dictionary = clans[id]
	var house_clan := bool(c.get("hc", false))
	if _cool_left(pid) > 0 and not house_clan:
		soc._note(pid, "You can join a clan again in %s" % hours_text(_cool_left(pid)), true)
		return
	if (c.members as Dictionary).size() >= max_of(c):
		soc._note(pid, "%s is full (%d)" % [str(c.name), max_of(c)], true)
		return
	if invites.get(pid, {}).has(id):
		_out_of_house(pid)
		_add_member(id, pid, "")
		return
	if _level(pid) < int(c.min_lv):
		soc._note(pid, "%s needs level %d" % [str(c.name), int(c.min_lv)], true)
		return
	match str(c.join):
		"open":
			_out_of_house(pid)
			_add_member(id, pid, "")
		"request":
			if (c.req as Dictionary).has(pid):
				soc._note(pid, "Request already sent")
				return
			c.req[pid] = unix()
			while (c.req as Dictionary).size() > MAX_REQUESTS:
				var oldest := ""
				var ot := 1 << 62
				for r in c.req:
					if int(c.req[r]) < ot:
						ot = int(c.req[r])
						oldest = str(r)
				c.req.erase(oldest)
			_mark()
			soc.event_fn.call(str(soc.users[pid].acct), "clan_request", {})
			soc._note(pid, "Request sent to [%s] %s" % [str(c.tag), str(c.name)])
			var pop_key := id + ":" + pid
			var pop: bool = unix() - int(_asked_pop.get(pop_key, 0)) > ASK_POP_GAP
			if pop:
				_asked_pop[pop_key] = unix()
			for o in members_of(id):
				if _is_officer(str(o)):
					_refresh(str(o))
					if pop:                                # (asking again and again pops up once an hour)
						soc._send(str(o), {"t":"so", "k":"note", "x":"%s asked to join the clan" % _name(pid), "pop":true})
			_refresh(pid)
		_:
			soc._note(pid, "%s is invite only" % str(c.name), true)

func _add_member(id: String, pid: String, by: String) -> void:
	var c: Dictionary = clans[id]
	c.members[pid] = unix()
	c.req.erase(pid)
	member_of[pid] = id
	_drop_pending(pid)
	_mark()
	soc.event_fn.call(str(soc.users[pid].acct), "clan_join", {"n":(c.members as Dictionary).size()})
	if bool(c.get("hc", false)):
		_refresh(pid)                                  # (a house clan: no line, and only the newcomer's state)
	else:
		_sys(id, ("%s joined the clan" % _name(pid)) if by == "" else ("%s let %s in" % [_name(by), _name(pid)]))
		_refresh_all(id)
	soc._send(pid, {"t":"so", "k":"hist", "ch":"clan", "list":soc._visible(pid, soc.hist.get("c:" + id, []))})
	soc._send(pid, {"t":"so", "k":"note", "x":"Welcome to [%s] %s!" % [str(c.tag), str(c.name)], "pop":true})
	_presence_tag(pid)

func _unreq(pid: String, id: String) -> void:
	if clans.has(id) and (clans[id].req as Dictionary).has(pid):
		clans[id].req.erase(pid)
		_mark()
		for o in members_of(id):
			if _is_officer(str(o)):
				_refresh(str(o))
	_refresh(pid)

func _noinv(pid: String, id: String) -> void:
	var mine: Dictionary = invites.get(pid, {})
	if mine.has(id):
		mine.erase(id)
		if mine.is_empty():
			invites.erase(pid)
		_mark()
	_refresh(pid)

func _accept(pid: String, target: String) -> void:
	var id: String = member_of.get(pid, "")
	if id == "" or not _is_officer(pid):
		return
	var c: Dictionary = clans[id]
	if not (c.req as Dictionary).has(target):
		_refresh(pid)
		return
	if (member_of.has(target) and not is_house(str(member_of[target]))) or not soc.users.has(target):
		c.req.erase(target)
		_mark()
		soc._note(pid, "%s is in another clan now" % _name(target), true)
		_refresh_all(id)
		return
	if (c.members as Dictionary).size() >= MAX_MEMBERS:
		soc._note(pid, "The clan is full (%d)" % MAX_MEMBERS, true)
		return
	if _cool_left(target) > 0:
		soc._note(pid, "%s can't join a clan for another %s" % [_name(target), hours_text(_cool_left(target))], true)
		return
	_out_of_house(target)
	_add_member(id, target, pid)

func _reject(pid: String, target: String) -> void:
	var id: String = member_of.get(pid, "")
	if id == "" or not _is_officer(pid):
		return
	if (clans[id].req as Dictionary).has(target):
		clans[id].req.erase(target)
		_mark()
	for o in members_of(id):
		if _is_officer(str(o)):
			_refresh(str(o))
	_refresh(target)

func _invite(pid: String, target: String) -> void:
	var id: String = member_of.get(pid, "")
	if id == "" or not _is_officer(pid):
		soc._note(pid, "Only the leader and officers can invite", true)
		return
	if target == pid or not soc.users.has(target):
		soc._note(pid, "No player with that friend code", true)
		return
	var c: Dictionary = clans[id]
	if member_of.get(target, "") == id:
		soc._note(pid, "%s is in the clan already" % _name(target))
		return
	if member_of.has(target) and not is_house(str(member_of[target])):
		soc._note(pid, "%s is in another clan" % _name(target), true)
		return
	if (c.members as Dictionary).size() >= MAX_MEMBERS:
		soc._note(pid, "The clan is full (%d)" % MAX_MEMBERS, true)
		return
	soc._note(pid, "Invited %s to the clan" % _name(target))
	if (soc.users[target].get("blocked", []) as Array).has(pid):
		return                                         # (blocked: it looks sent, and never arrives)
	var mine: Dictionary = invites.get(target, {})
	var again := mine.has(id)
	mine[id] = {"by":pid, "at":unix()}
	while mine.size() > MAX_INVITES:
		var oldest := ""
		var ot := 1 << 62
		for k in mine:
			if int(mine[k].at) < ot:
				ot = int(mine[k].at)
				oldest = str(k)
		mine.erase(oldest)
	invites[target] = mine
	_mark()
	if again:
		return                                         # (invited already: the invite is fresh again, no second pop-up)
	soc.event_fn.call(str(soc.users[pid].acct), "clan_invite", {})
	soc._send(target, {"t":"so", "k":"clan_inv", "c":summary(c), "by":soc._card(pid)})
	_refresh(target)

func _remove(id: String, pid: String) -> void:
	# out of the clan (no cooldown here): a leader's place goes on; the last one out ends the clan
	var c: Dictionary = clans[id]
	c.members.erase(pid)
	(c.officers as Array).erase(pid)
	(c.ask as Dictionary).erase(pid)                   # 0.31.196: their shard request, their LFG call
	member_of.erase(pid)
	if soc.has_method("lfg_drop"):
		soc.lfg_drop(pid)
	_mark()
	if bool(c.get("hc", false)):
		return                                         # (0.31.148: a house clan stays, empty or not; nobody leads it)
	if (c.members as Dictionary).is_empty():
		_end(id)
		return
	if str(c.leader) == pid:
		var next := _successor(c, pid)
		c.leader = next
		(c.officers as Array).erase(next)
		_sys(id, "%s leads the clan now" % _name(next))

func _end(id: String) -> void:
	clans.erase(id)
	soc.hist.erase("c:" + id)
	soc._mark()                                        # (0.31.140: out of chat.json too)
	for pid in invites.keys():
		(invites[pid] as Dictionary).erase(id)
		if (invites[pid] as Dictionary).is_empty():
			invites.erase(pid)
	_mark()
	soc.log_fn.call("clan %s ended" % id)

func _leave(pid: String) -> void:
	var id: String = member_of.get(pid, "")
	if id == "":
		_refresh(pid)
		return
	var house_clan := is_house(id)
	if not house_clan:
		_sys(id, "%s left the clan" % _name(pid))
	_remove(id, pid)
	if clans.has(id) and not house_clan:
		cool[pid] = unix() + COOLDOWN                  # (the last one out ended the clan: like disbanding, no wait; a house clan: none)
	_mark()
	soc.event_fn.call(str(soc.users.get(pid, {}).get("acct", "")), "clan_leave", {})
	_refresh(pid)
	soc._send(pid, {"t":"so", "k":"hist", "ch":"clan", "list":[]})
	if clans.has(id) and not house_clan:
		_refresh_all(id)
	_presence_tag(pid)

func _kick(pid: String, target: String) -> void:
	var id: String = member_of.get(pid, "")
	if id == "" or target == pid or member_of.get(target, "") != id:
		return
	var mine := role_of(pid)
	var theirs := role_of(target)
	if not (mine == "leader" or (mine == "officer" and theirs == "member")):
		soc._note(pid, "Only the leader can remove an officer", true)
		return
	var c: Dictionary = clans[id]
	_sys(id, "%s was removed from the clan" % _name(target))
	_remove(id, target)
	cool[target] = unix() + COOLDOWN
	_mark()
	soc._send(target, {"t":"so", "k":"note", "x":"You were removed from [%s] %s" % [str(c.tag), str(c.name)], "bad":true, "pop":true})
	_refresh(target)
	soc._send(target, {"t":"so", "k":"hist", "ch":"clan", "list":[]})
	_refresh_all(id)
	_presence_tag(target)

func _role(pid: String, target: String, role: String) -> void:
	var id: String = member_of.get(pid, "")
	if id == "" or role_of(pid) != "leader" or target == pid or member_of.get(target, "") != id:
		return
	var c: Dictionary = clans[id]
	var offs: Array = c.officers
	if role == "officer" and not offs.has(target):
		offs.append(target)
		_sys(id, "%s is an officer now" % _name(target))
	elif role == "member" and offs.has(target):
		offs.erase(target)
		_sys(id, "%s is a member again" % _name(target))
	else:
		return
	_mark()
	_refresh_all(id)

func _lead(pid: String, target: String) -> void:
	var id: String = member_of.get(pid, "")
	if id == "" or role_of(pid) != "leader" or target == pid or member_of.get(target, "") != id:
		return
	var c: Dictionary = clans[id]
	c.leader = target
	(c.officers as Array).erase(target)
	if not (c.officers as Array).has(pid):
		(c.officers as Array).append(pid)
	_mark()
	_sys(id, "%s handed the clan to %s" % [_name(pid), _name(target)])
	_refresh_all(id)

func _settings(pid: String, msg: Dictionary) -> void:
	var id: String = member_of.get(pid, "")
	if id == "" or not _is_officer(pid):
		return
	var c: Dictionary = clans[id]
	var changed := []
	var join := str(msg.get("join", c.join))
	if join in JOIN_MODES and join != str(c.join):
		c.join = join
		changed.append({"open":"open to all", "request":"join by request", "invite":"invite only"}[join])
	if msg.has("min_lv"):
		var lv := clampi(int(msg.min_lv), 1, MIN_LV_MAX)
		if lv != int(c.min_lv):
			c.min_lv = lv
			changed.append("level %d and up" % lv)
	if changed.is_empty():
		return
	_mark()
	_sys(id, "%s set the clan to %s" % [_name(pid), ", ".join(changed)])
	_refresh_all(id)

func _disband(pid: String) -> void:
	var id: String = member_of.get(pid, "")
	if id == "" or role_of(pid) != "leader":
		return
	var c: Dictionary = clans[id]
	var all := members_of(id)
	for m in all:
		member_of.erase(str(m))
	_end(id)
	soc.log_fn.call("clan %s [%s] disbanded by %s" % [id, str(c.tag), pid])
	for m in all:
		var mp := str(m)
		if mp != pid:
			soc._send(mp, {"t":"so", "k":"note", "x":"%s disbanded [%s] %s" % [_name(pid), str(c.tag), str(c.name)], "bad":true, "pop":true})
		_refresh(mp)
		soc._send(mp, {"t":"so", "k":"hist", "ch":"clan", "list":[]})
		_presence_tag(mp)

func blocked(pid: String, target: String) -> void:
	# social.gd: pid blocked target -- target's invites to pid go
	var mine: Dictionary = invites.get(pid, {})
	var gone := false
	for id in mine.keys():
		if str(mine[id].get("by", "")) == target:
			mine.erase(id)
			gone = true
	if mine.is_empty():
		invites.erase(pid)
	if gone:
		_mark()
		_refresh(pid)

func forget(pid: String) -> void:
	# the account was deleted (social.gd forget): out of its clan, its invites, requests and cooldown gone
	var id: String = member_of.get(pid, "")
	if id != "":
		var house_clan := is_house(id)
		if not house_clan:
			_sys(id, "%s left the clan" % _name(pid))
		_remove(id, pid)
		if clans.has(id) and not house_clan:
			_refresh_all(id)
	invites.erase(pid)
	cool.erase(pid)
	for cid in clans:
		(clans[cid].req as Dictionary).erase(pid)
	_mark()

# ---------------- 0.31.196: the crest, clan points, the week (Clan Chest, League), shard requests ----------------
static func league_before(a: Dictionary, b: Dictionary, wk: String) -> bool:
	# the League's order: the week's points, then XP, then the older clan
	var pa := int(a.wk.pts) if str(a.wk.get("week", "")) == wk else 0
	var pb := int(b.wk.pts) if str(b.wk.get("week", "")) == wk else 0
	if pa != pb:
		return pa > pb
	if int(a.get("xp", 0)) != int(b.get("xp", 0)):
		return int(a.get("xp", 0)) > int(b.get("xp", 0))
	return int(a.get("created", 0)) < int(b.get("created", 0))

func post(id: String, pid: String, text: String, extra: Dictionary) -> void:
	# a player's line in the clan's chat that the game writes for him -- a shard request ("ask": the hero), an LFG call
	# ("lfg": his party's size) -- with the buttons the phone puts on it
	if not clans.has(id):
		return
	var u: Dictionary = soc.users.get(pid, {})
	var m := {"id":soc.next_msg, "ch":"clan", "pid":pid, "n":str(u.get("name", "Player")), "tt":str(u.get("title", "")),
		"x":text, "at":unix(), "ct":str(clans[id].tag), "cc":Eco.crest_code(clans[id].crest)}
	m.merge(extra)
	soc.next_msg += 1
	soc._hist_add("c:" + id, m, HIST_CLAN)
	for mp in members_of(id):
		if not (soc.users.get(str(mp), {}).get("blocked", []) as Array).has(pid):
			soc._send(str(mp), {"t":"so", "k":"chat", "m":m})

func _crest(pid: String, msg: Dictionary) -> void:
	var id: String = member_of.get(pid, "")
	if id == "" or not clans.has(id) or is_house(id):
		return
	if not _is_officer(pid):
		soc._note(pid, "Only the leader and officers can change the crest", true)
		return
	var cr := Eco.clean_crest(msg.get("cr", null))
	var c: Dictionary = clans[id]
	if cr.is_empty() or Eco.crest_code(cr) == Eco.crest_code(c.crest):
		return
	c.crest = cr
	_mark()
	_sys(id, "%s gave the clan a new crest" % _name(pid))
	_refresh_all(id)
	for m in members_of(id):
		_presence_tag(str(m))

func _gain_xp(id: String, n: int) -> void:
	# clan XP (a players' clan): its level, the camp's stage -- a line in its chat when either grows
	var c: Dictionary = clans[id]
	var lv0 := level_of(c)
	c.xp = int(c.get("xp", 0)) + n
	var lv1 := level_of(c)
	if lv1 > lv0:
		var grew := Eco.clan_camp_stage(lv1) > Eco.clan_camp_stage(lv0)
		_sys(id, "The clan reached level %d!%s" % [lv1, " The camp grew." if grew else ""])

func add_match(acct: String, me: Dictionary, won: bool, draw: bool, mates: Array) -> int:
	# siege_server _pay_match: an online match paid -- its clan points for the player's clan (a players' clan), doubled
	# when a clanmate was in his party (mates: the accounts of the party's members in that match). -> the points
	var pid := str(soc.pid_of(acct)) if acct != "" else ""
	var id: String = member_of.get(pid, "") if pid != "" else ""
	if id == "" or not clans.has(id) or is_house(id):
		return 0
	_roll()
	var c: Dictionary = clans[id]
	var p := Eco.clan_points(me, won, draw)
	for a in mates:
		var mp := str(soc.pid_of(str(a)))
		if mp != "" and mp != pid and member_of.get(mp, "") == id:
			p *= Eco.CLAN_PARTY_X
			break
	if str(c.wk.get("week", "")) != week:
		c.wk = {"week":week, "pts":0, "by":{}}
	var tier0 := Eco.clan_tier(int(c.wk.pts))
	c.wk.pts = int(c.wk.pts) + p
	c.wk.by[pid] = int(c.wk.by.get(pid, 0)) + p
	_gain_xp(id, p)
	var tier1 := Eco.clan_tier(int(c.wk.pts))
	if tier1 > tier0:
		_sys(id, "The Clan Chest reached %s! Everyone with %d+ points this week gets it on Monday." % [
			str(Eco.CHESTS[Eco.clan_chest_of(tier1)].name), Eco.CLAN_CHEST_MIN])
	_mark()
	_push[id] = true
	return p

func _roll() -> void:
	# a new week (Monday 00:00 UTC): the one that ended is settled, every clan starts the new one at 0
	var w := Leaderboard.week_of(unix())
	if w == week:
		return
	if week != "":
		_settle(week)
	week = w
	for id in clans:
		clans[id].wk = {"week":w, "pts":0, "by":{}}
		if not is_house(str(id)):
			_push[str(id)] = true
	_mark()
	save_now()

func _settle(w: String) -> void:
	# week w is over: each players' clan that earned points is paid -- its Clan Chest and its League place's gems to every
	# member who earned Eco.CLAN_CHEST_MIN; the top three wear their frame this week
	var ranked := []
	for id in clans:
		var c: Dictionary = clans[id]
		c.fr = ""
		if is_house(str(id)):
			continue
		if str(c.wk.get("week", "")) != w or int(c.wk.pts) <= 0:
			c.last = {"week":w, "pts":0, "rank":0, "tier":0, "chest":"", "gems":0, "paid":0}
			continue
		ranked.append(c)
	ranked.sort_custom(func(a, b): return league_before(a, b, w))
	league_last = []
	var n_paid := 0
	var eco = soc.eco
	for i in ranked.size():
		var c: Dictionary = ranked[i]
		var rank := i + 1
		var pts := int(c.wk.pts)
		var tier := Eco.clan_tier(pts)
		var chest := Eco.clan_chest_of(tier)
		var pr := Eco.clan_league_prize(rank)
		var gems := int(pr.get("gems", 0))
		c.fr = str(pr.get("frame", ""))
		var paid := 0
		if (chest != "" or gems > 0) and eco != null and eco.has_method("grant_clan_reward"):
			for mp in c.wk.by:
				var who := str(mp)
				if int(c.wk.by[mp]) < Eco.CLAN_CHEST_MIN or not (c.members as Dictionary).has(who) or not soc.users.has(who):
					continue
				var r := {"chest":chest, "gems":gems, "rank":rank, "tier":tier, "clan":str(c.name), "tag":str(c.tag), "pts":pts}
				if bool(eco.grant_clan_reward(str(soc.users[who].acct), w, r)):
					paid += 1
					soc._send(who, {"t":"so", "k":"eco"})          # (their phone fetches the account: the chest is in it)
		n_paid += paid
		c.last = {"week":w, "pts":pts, "rank":rank, "tier":tier, "chest":chest, "gems":gems, "paid":paid, "fr":str(c.fr)}
		if rank <= 3:
			league_last.append({"name":str(c.name), "tag":str(c.tag), "cc":Eco.crest_code(c.crest), "pts":pts, "fr":str(c.fr)})
		var bits := ["%d points" % pts]
		if chest != "":
			bits.append("the %s" % str(Eco.CHESTS[chest].name))
		bits.append("#%d in the League%s" % [rank, (" (+%d gems)" % gems) if gems > 0 else ""])
		_sys(str(c.id), "Last week: %s." % ", ".join(bits))
	soc.log_fn.call("clans: week %s settled, %d clans ranked, %d members paid; first %s" % [w, ranked.size(), n_paid,
		str(ranked[0].name) if not ranked.is_empty() else "-"])

func _ask(pid: String, h: String) -> void:
	var id: String = member_of.get(pid, "")
	if id == "" or not clans.has(id):
		soc._note(pid, "Join a clan first", true)
		return
	if not Eco.HERO_PRICES.has(h):
		return
	var c: Dictionary = clans[id]
	if (c.ask as Dictionary).has(pid):
		soc._note(pid, "You already have a request open", true)
		return
	var left := int(asked_at.get(pid, 0)) + Eco.CLAN_ASK_GAP - unix()
	if left > 0:
		soc._note(pid, "You can ask again in %s" % hours_text(left), true)
		return
	var eco = soc.eco
	var hs: Dictionary = eco.heroes_of(str(soc.users[pid].acct)) if eco != null and eco.has_method("heroes_of") else {}
	if hs.is_empty():
		soc._note(pid, "Couldn't ask right now -- try again", true)
		return
	if (hs.get("own", []) as Array).has(h):
		soc._note(pid, "You have %s already" % h.capitalize(), true)
		return
	c.ask[pid] = {"h":h, "at":unix()}
	asked_at[pid] = unix()
	_mark()
	soc.event_fn.call(str(soc.users[pid].acct), "clan_ask", {"hero":h})
	post(id, pid, "Asks for a %s shard" % h.capitalize(), {"ask":h})
	_refresh_all(id)

func _unask(pid: String) -> void:
	var id: String = member_of.get(pid, "")
	if id == "" or not clans.has(id) or not (clans[id].ask as Dictionary).has(pid):
		return
	clans[id].ask.erase(pid)
	_mark()
	_refresh_all(id)

func _give(pid: String, target: String) -> void:
	var id: String = member_of.get(pid, "")
	if id == "" or not clans.has(id) or target == pid or member_of.get(target, "") != id:
		return
	var c: Dictionary = clans[id]
	if not (c.ask as Dictionary).has(target):
		soc._note(pid, "That request is over")
		_refresh(pid)
		return
	var h := str(c.ask[target].h)
	var eco = soc.eco
	if eco == null or not eco.has_method("give_shard"):
		return
	var r: Dictionary = eco.give_shard(str(soc.users[pid].acct), str(soc.users[target].acct), h)
	if not bool(r.get("ok", false)):
		var why := str(r.get("error", ""))
		if why == "owned":
			c.ask.erase(target)                            # (they have the hero now: the request is over)
			_mark()
			_refresh_all(id)
		soc._note(pid, {"no_shard":"You don't have a %s shard" % h.capitalize(), "owned":"%s has %s already" % [_name(target), h.capitalize()],
			"gifted":"Your %s shard was a clanmate's gift -- it can't be given on" % h.capitalize()}.get(why,
			"Couldn't give it right now -- try again"), true)
		return
	c.ask.erase(target)
	if not is_house(id):
		_gain_xp(id, Eco.CLAN_GIVE_XP)
	_mark()
	soc.event_fn.call(str(soc.users[pid].acct), "clan_give", {"hero":h})
	_sys(id, "%s gave %s a %s shard" % [_name(pid), _name(target), h.capitalize()])
	soc._send(pid, {"t":"so", "k":"eco"})
	soc._send(target, {"t":"so", "k":"eco"})
	soc._note(pid, "Thanks! +%d gold for the %s shard" % [int(r.get("gold", 0)), h.capitalize()])
	soc._send(target, {"t":"so", "k":"note", "x":"%s gave you a %s shard!" % [_name(pid), h.capitalize()], "pop":true})
	_refresh_all(id)

func league_rows() -> Array:
	# this week's players' clans with points, League order
	var list := []
	for id in clans:
		if not is_house(str(id)) and week_pts(clans[id]) > 0:
			list.append(clans[id])
	list.sort_custom(func(a, b): return league_before(a, b, week))
	return list

func _league(pid: String) -> void:
	_roll()
	var list := league_rows()
	var my_id: String = member_of.get(pid, "")
	var rows := []
	var mine := {}
	for i in list.size():
		var c: Dictionary = list[i]
		var row := {"rank":i + 1, "id":str(c.id), "name":str(c.name), "tag":str(c.tag), "cc":Eco.crest_code(c.crest),
			"pts":week_pts(c), "lv":level_of(c), "n":(c.members as Dictionary).size()}
		if str(c.get("fr", "")) != "":
			row["fr"] = str(c.fr)
		if str(c.id) == my_id:
			row["you"] = true
			mine = row
		if i < LEAGUE_TOP:
			rows.append(row)
	soc._send(pid, {"t":"so", "k":"clan_league", "week":week, "ends":Leaderboard.week_end(unix()), "list":rows, "me":mine,
		"clans":list.size(), "last":league_last})
