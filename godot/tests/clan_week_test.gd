extends SceneTree
# 0.31.196 (Kevin: "Do clan chest, clan camp, crest, shard requests, 5 - stack, lfg button, league"): server/clans.gd and
# server/social.gd's new parts with fake sockets and a stand-in for the accounts --
#   - the crest: picked when a clan is made (no house needed; an older app's house brings its crest), changed by the
#     leader and officers only, on the clan's summary, cards and chat lines ("cc");
#   - clan points from add_match (Eco.clan_points; doubled with a clanmate in the party; none in a house clan), the
#     week's points and who earned them, XP and the level (a chat line when it grows), the Clan Chest's tiers;
#   - the week's end: each members with Eco.CLAN_CHEST_MIN points gets the chest and the League place's gems (once),
#     their phones told to fetch the account, the podium's frames, "last", a chat line; every clan starts at 0;
#   - clan_league: the table in order, my clan's row;
#   - shard requests: ask (not for a hero you own, one at a time, Eco.CLAN_ASK_GAP between), give (the giver's shard
#     and melt gold, the asker's shard, clan XP, both phones told), take back; they run out;
#   - parties of 5, invites to clanmates who aren't friends, LFG (a call in clan chat, JOIN into the caller's party,
#     made then if he had none; outsiders and full parties refused; the call ends when the party fills).
#   godot --headless --path godot -s res://tests/clan_week_test.gd
const Social = preload("res://server/social.gd")
const Clans = preload("res://server/clans.gd")
const Leaderboard = preload("res://server/leaderboard.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const Accounts = preload("res://server/eco_accounts.gd")
const Profile = preload("res://scripts/meta/profile.gd")

var fails: Array = []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

class FakeEco:
	var accts := {}
	var rewards := []                     # [acct, week, r]
	func add(id: String, name: String, gold: int, lv: int) -> void:
		accts[id] = {"name":name, "gold":gold, "lv":lv, "own":[], "shards":[], "weeks":[]}
	func open(id: String, key: String) -> Dictionary:
		return {"id":id} if accts.has(id) and key == "k".repeat(64) else {}
	func public_of(id: String) -> Dictionary:
		return {"name":str(accts[id].name), "title":""} if accts.has(id) else {}
	func stats_of(id: String) -> Dictionary:
		return {"lv":int(accts[id].lv)} if accts.has(id) else {}
	func pay_gold(id: String, amount: int, _why: String) -> bool:
		if not accts.has(id) or int(accts[id].gold) < amount:
			return false
		accts[id].gold = int(accts[id].gold) - amount
		return true
	func grant_clan_reward(id: String, week: String, r: Dictionary) -> bool:
		if not accts.has(id) or (accts[id].weeks as Array).has(week):
			return false
		accts[id].weeks.append(week)
		rewards.append([id, week, r])
		return true
	func heroes_of(id: String) -> Dictionary:
		return {"own":(accts[id].own as Array).duplicate(), "shards":(accts[id].shards as Array).duplicate()} if accts.has(id) else {}
	func give_shard(from_id: String, to_id: String, hid: String) -> Dictionary:
		if (accts[to_id].own as Array).has(hid):
			return {"ok":false, "error":"owned"}
		if not (accts[from_id].shards as Array).has(hid):
			return {"ok":false, "error":"no_shard"}
		accts[from_id].shards.erase(hid)
		accts[from_id].gold = int(accts[from_id].gold) + 777
		accts[to_id].shards.append(hid)
		return {"ok":true, "gold":777}

var inbox := {}                          # socket id -> [messages]

func got(cid: int, k: String) -> Array:
	return (inbox.get(cid, []) as Array).filter(func(m): return str(m.get("k", "")) == k)

func last(cid: int, k: String) -> Dictionary:
	var l := got(cid, k)
	return l[l.size() - 1] if not l.is_empty() else {}

func clan(cid: int) -> Dictionary:
	return last(cid, "clan").get("clan", {})

func notes(cid: int) -> String:
	return " | ".join(got(cid, "note").map(func(m): return str(m.get("x", ""))))

func chat_lines(cid: int) -> Array:
	return got(cid, "chat").map(func(m): return m.get("m", {}))

func clear() -> void:
	inbox = {}

func _init() -> void:
	var dir := OS.get_user_data_dir().path_join("clanweek-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(dir)
	var eco := FakeEco.new()
	var names := ["Alice", "Bob", "Cara", "Dan", "Eve", "Finn", "Gus", "Hana"]
	var ids := []
	for i in names.size():
		var id := "%020x" % (i + 1)
		eco.add(id, names[i], 20000, 10)
		ids.append(id)
	# a Tuesday, 2026-10-20 12:00 UTC (the week of Monday 2026-10-19)
	var T0 := 1792497600
	var s = Social.new(dir, eco)
	s.now_override = T0
	s.send_fn = func(cid, msg):
		var l: Array = inbox.get(cid, [])
		l.append(msg)
		inbox[cid] = l
	s.clans = Clans.new(dir, s)
	var cl = s.clans
	var P := []
	for i in names.size():
		s.hello(i + 1, {"k":"hi", "acct":ids[i], "key":"k".repeat(64)})
		P.append(Social.pid_of(ids[i]))
	var A: String = P[0]
	var B: String = P[1]
	var C: String = P[2]
	var D: String = P[3]
	var E: String = P[4]
	var F: String = P[5]
	var G: String = P[6]
	var H: String = P[7]
	check(int(last(1, "me").get("lfg", 0)) == 1 and Social.PARTY_MAX == 5, "\"me\" says LFG is here; parties are up to 5")
	check(Leaderboard.week_of(T0) == "2026-10-19", "the test's week starts Monday 2026-10-19")

	# ---------------- the crest ----------------
	clear()
	s.handle(1, {"k":"clan_new", "name":"Iron Wolves", "tag":"WOLF", "cr":{"e":3, "f":5, "c":1}, "join":"open"})
	var mine := clan(1)
	check(bool(last(1, "clan_made").get("ok", false)) and str(mine.get("cc", "")) == "3.5.1" and int(mine.get("cv", 0)) == 2
		and int(mine.get("lv", 0)) == 1 and int(mine.get("pts", -1)) == 0 and str(mine.get("house", "")) == "lions",
		"a clan made with a crest and no house: its crest on the summary, level 1, 0 points (older apps see a house): %s" % str(mine))
	var wolves: String = cl.clan_of(A)
	check(str(chat_lines(1)[0].get("x", "")) == "Alice founded Iron Wolves", "the founding line names no house")
	clear()
	s.handle(2, {"k":"clan_new", "name":"Bad Crest", "tag":"BAD", "cr":{"e":99, "f":0, "c":0}})
	check(str(last(2, "clan_made").get("why", "")) == "crest" and int(eco.accts[ids[1]].gold) == 20000, "a crest that isn't one: refused, no gold taken")
	clear()
	s.handle(2, {"k":"clan_new", "name":"Old App Clan", "tag":"OLD", "house":"ravens"})
	check(bool(last(2, "clan_made").get("ok", false)) and str(clan(2).get("cc", "")) == Eco.crest_code(Eco.CLAN_HOUSE_CREST.ravens)
		and str(clan(2).house) == "ravens", "an older app's clan (a house, no crest): the house's crest")
	var old: String = cl.clan_of(B)
	for p in [C, D, E, F]:
		s.handle(P.find(p) + 1, {"k":"clan_join", "id":wolves})
	check(cl.members_of(wolves).size() == 5, "Cara, Dan, Eve and Finn join the Wolves")
	s.tick(Clans.MSG_WINDOW + 1.0)
	clear()
	s.handle(3, {"k":"clan_crest", "cr":{"e":0, "f":0, "c":0}})
	check(str(cl.crest_of(A)) == "3.5.1" and notes(3).contains("leader and officers"), "a member can't change the crest")
	s.handle(1, {"k":"clan_role", "pid":C, "role":"officer"})
	clear()
	s.handle(3, {"k":"clan_crest", "cr":{"e":4, "f":1, "c":2}})
	check(str(cl.crest_of(A)) == "4.1.2" and str(clan(1).get("cc", "")) == "4.1.2" and str(clan(5).get("cc", "")) == "4.1.2"
		and chat_lines(1).any(func(m): return str(m.get("x", "")).contains("new crest")), "an officer can: everyone's state has it, and a line in chat")
	check(str(s._card(A).get("cc", "")) == "4.1.2" and str(cl.crest_of_acct(ids[0])) == "4.1.2", "cards carry the crest")
	s.tick(Clans.MSG_WINDOW + 1.0)
	clear()
	s.handle(1, {"k":"chat", "ch":"clan", "x":"hello wolves"})
	var line: Dictionary = last(2 + 1, "chat").get("m", {})
	check(str(line.get("cc", "")) == "4.1.2" and str(line.get("ct", "")) == "WOLF", "a clan chat line carries the tag and crest")
	s.tick(2.0)

	# ---------------- clan points ----------------
	clear()
	var p1: int = cl.add_match(ids[0], {"kills":3, "towers":1}, true, false, [])
	check(p1 == 10 + 2 + 3 and int(cl.clans[wolves].wk.pts) == 15 and int(cl.clans[wolves].wk.by[A]) == 15 and int(cl.clans[wolves].xp) == 15,
		"a win with 3 KOs and a tower: %d points (10 + 2 + 3), the week's and the XP" % p1)
	var p2: int = cl.add_match(ids[2], {"kills":20, "towers":0}, false, false, [ids[0], ids[7]])
	check(p2 == (4 + 10) * Eco.CLAN_PARTY_X, "a loss with 20 KOs (KOs count up to 10) and a clanmate in the party: doubled to %d" % p2)
	var p3: int = cl.add_match(ids[3], {"kills":0}, false, true, [ids[7]])
	check(p3 == 6, "a draw with only an outsider in the party: %d, not doubled" % p3)
	var p4: int = cl.add_match(ids[7], {"kills":5}, true, false, [])
	check(p4 == 0, "a player in no clan: no points")
	s.handle(8, {"k":"clan_join", "id":Clans.HOUSE_CLANS.lions.id})
	check(cl.add_match(ids[7], {"kills":5}, true, false, []) == 0 and int(cl.clans[Clans.HOUSE_CLANS.lions.id].wk.pts) == 0, "a house clan earns none")
	check(int(cl.clans[wolves].wk.pts) == 15 + 28 + 6, "the Wolves' week: %d" % int(cl.clans[wolves].wk.pts))
	s.tick(Clans.PUSH_EVERY + 0.1)
	var st := clan(1)
	check(int(st.get("pts", 0)) == 49 and int(st.get("mine_pts", 0)) == 15 and int(st.get("xp", 0)) == 49 and int(st.get("tier", -1)) == 0
		and str(st.get("week", "")) == "2026-10-19" and int(st.get("ends", 0)) == Leaderboard.week_end(T0),
		"the members' state goes out a moment later: the week's points, mine, XP, the tier, the week and its end")
	var cards: Array = st.get("members", [])
	check(cards.any(func(c): return str(c.pid) == C and int(c.get("wp", 0)) == 28), "each member's card carries his points this week")
	clear()
	cl.add_match(ids[4], {"kills":2}, true, false, [])           # 49 + 12 = 61: the Wooden Chest
	check(chat_lines(1).any(func(m): return str(m.get("x", "")).contains("Clan Chest reached Wooden")), "reaching a tier: a line in the clan's chat")
	for i in 12:
		cl.add_match(ids[5], {"kills":2, "towers":1}, true, false, [ids[0]])   # 28 a match, doubled
	check(int(cl.clans[wolves].wk.pts) >= 200 and cl.level_of(cl.clans[wolves]) == Eco.clan_level(int(cl.clans[wolves].xp)) and cl.level_of(cl.clans[wolves]) >= 2,
		"enough points: the Silver tier and level %d" % cl.level_of(cl.clans[wolves]))
	check(chat_lines(1).any(func(m): return str(m.get("x", "")).contains("reached level 2")), "...and a line when the clan levels up")
	# another clan, fewer points
	cl.add_match(ids[1], {"kills":1}, false, false, [])
	check(int(cl.clans[old].wk.pts) == 5, "Bob's clan: 5 points")

	# ---------------- the League ----------------
	clear()
	s.handle(1, {"k":"clan_league"})
	var lg := last(1, "clan_league")
	var rows: Array = lg.get("list", [])
	check(rows.size() == 2 and str(rows[0].tag) == "WOLF" and int(rows[0].rank) == 1 and bool(rows[0].get("you", false)) and str(rows[1].tag) == "OLD"
		and str(lg.get("me", {}).get("tag", "")) == "WOLF" and str(rows[0].cc) == "4.1.2", "the League: the Wolves first, then Bob's; my row marked")
	check(not rows.any(func(r): return str(r.tag) == "LION" or str(r.tag) == "LNG"), "house clans aren't in the League")

	# ---------------- shard requests ----------------
	eco.accts[ids[2]].shards = ["golem", "golem"]
	eco.accts[ids[4]].own = ["druid"]
	s.tick(Clans.MSG_WINDOW + 1.0)
	clear()
	s.handle(5, {"k":"clan_ask", "h":"druid"})
	check(not (cl.clans[wolves].ask as Dictionary).has(E) and notes(5).contains("already"), "asking for a hero you own: refused")
	s.handle(5, {"k":"clan_ask", "h":"golem"})
	check(str(cl.clans[wolves].ask[E].h) == "golem", "Eve asks for a Golem shard")
	var ask_line: Dictionary = chat_lines(1).filter(func(m): return m.has("ask")).back() if chat_lines(1).any(func(m): return m.has("ask")) else {}
	check(str(ask_line.get("ask", "")) == "golem" and str(ask_line.get("pid", "")) == E and str(ask_line.get("x", "")).contains("Golem"),
		"a line in clan chat with the request (for the GIVE button)")
	check((clan(1).get("asks", []) as Array).any(func(a): return str(a.pid) == E and str(a.h) == "golem"), "the clan's state lists it")
	clear()
	s.handle(5, {"k":"clan_ask", "h":"dragoon"})
	check((cl.clans[wolves].ask[E].h) == "golem" and notes(5).contains("already have a request"), "one request at a time")
	clear()
	s.handle(4, {"k":"clan_give", "pid":E})
	check((cl.clans[wolves].ask as Dictionary).has(E) and notes(4).contains("don't have a Golem shard"), "Dan has no Golem shard: nothing given")
	var xp0 := int(cl.clans[wolves].xp)
	clear()
	s.handle(3, {"k":"clan_give", "pid":E})
	check(not (cl.clans[wolves].ask as Dictionary).has(E) and (eco.accts[ids[2]].shards as Array).size() == 1 and (eco.accts[ids[4]].shards as Array).has("golem")
		and int(eco.accts[ids[2]].gold) == 20777, "Cara gives one: it's Eve's, Cara gets its melt gold, the request is over")
	check(int(cl.clans[wolves].xp) == xp0 + Eco.CLAN_GIVE_XP and not got(3, "eco").is_empty() and not got(5, "eco").is_empty()
		and notes(5).contains("gave you a Golem shard") and chat_lines(1).any(func(m): return str(m.get("x", "")).contains("gave Eve a Golem shard")),
		"the clan gets %d XP, both phones are told to fetch their accounts, a line in chat" % Eco.CLAN_GIVE_XP)
	clear()
	s.handle(5, {"k":"clan_ask", "h":"dragoon"})
	check(not (cl.clans[wolves].ask as Dictionary).has(E) and notes(5).contains("ask again in 8 hours"), "the next request waits %d hours" % (Eco.CLAN_ASK_GAP / 3600))
	s.now_override = T0 + Eco.CLAN_ASK_GAP + 60
	s.handle(5, {"k":"clan_ask", "h":"dragoon"})
	s.handle(5, {"k":"clan_unask"})
	check(not (cl.clans[wolves].ask as Dictionary).has(E), "...then she may; and take it back")
	s.handle(6, {"k":"clan_ask", "h":"musketeer"})
	s.now_override = T0 + Eco.CLAN_ASK_GAP + 60 + Eco.CLAN_ASK_LIFE + 1
	cl.sweep()
	check(not (cl.clans[wolves].ask as Dictionary).has(F), "a request runs out after %d hours" % (Eco.CLAN_ASK_LIFE / 3600))
	s.now_override = T0 + 7200

	# ---------------- parties of 5, clanmates, LFG ----------------
	s.tick(Clans.MSG_WINDOW + 1.0)
	clear()
	s.handle(1, {"k":"invite", "pid":D})
	check((s.invites.get(D, {}) as Dictionary).size() == 1 and notes(1).contains("Invited Dan"), "a clanmate who isn't a friend can be invited")
	s.handle(1, {"k":"invite", "pid":H})
	check(not s.invites.has(H) and notes(1).contains("friends and clanmates"), "anyone else can't")
	s.handle(4, {"k":"nojoin", "party":s.party_of.get(A, "")})
	clear()
	s.handle(1, {"k":"lfg", "on":true})
	var lfg_line: Dictionary = {}
	for m in chat_lines(3):
		if str(m.get("lfg", "")) == A:
			lfg_line = m
	check(not lfg_line.is_empty() and str(lfg_line.get("x", "")).contains("1/5") and s.lfg.has(A), "Alice calls for players: a line in clan chat (1/5)")
	s.tick(Clans.PUSH_EVERY + 0.1)
	var calls: Array = clan(3).get("lfg", [])
	check(calls.size() == 1 and str(calls[0].pid) == A and int(calls[0].size) == 1 and int(calls[0].max) == 5, "the clan's state lists the call")
	clear()
	s.handle(8, {"k":"lfg_join", "pid":A})
	check(not s.party_of.has(H) and notes(8).contains("over"), "someone outside the clan can't JOIN")
	for p in [C, D, E, F]:
		s.handle(P.find(p) + 1, {"k":"lfg_join", "pid":A})
	var pa: String = s.party_of.get(A, "")
	check(pa != "" and (s.parties[pa].members as Array).size() == 5 and str(s.parties[pa].leader) == A and s.party_of.get(F, "") == pa,
		"four clanmates JOIN: a party of five, led by Alice")
	check(not s.lfg.has(A), "a full party ends the call")
	check(int(last(1, "party").get("party", {}).get("max", 0)) == 5, "the party says its size is 5")
	s.handle(2, {"k":"lfg_join", "pid":A})
	check(s.party_of.get(B, "") == "", "Bob (another clan) can't get in")
	s.handle(5, {"k":"lfg", "on":true})
	check(not s.lfg.has(E) and notes(5).contains("leader"), "a member of a party who isn't its leader can't call")
	s.handle(6, {"k":"leave"})
	s.handle(1, {"k":"lfg", "on":true})
	check(s.lfg.has(A) and int(s.lfg_of_clan(wolves)[0].size) == 4, "4/5 again: a new call")
	s.now_override = T0 + 7200 + Eco.CLAN_LFG_LIFE + 1
	s.tick(2.1)
	check(not s.lfg.has(A), "a call runs out after %d minutes" % (Eco.CLAN_LFG_LIFE / 60))
	s.now_override = T0 + 7200

	# ---------------- the week ends ----------------
	var by: Dictionary = (cl.clans[wolves].wk.by as Dictionary).duplicate()
	var wolf_pts := int(cl.clans[wolves].wk.pts)
	var tier := Eco.clan_tier(wolf_pts)
	clear()
	s.now_override = Leaderboard.week_end(T0) + 30
	s.tick(61.0)
	check(str(cl.week) == "2026-10-26" and int(cl.clans[wolves].wk.pts) == 0 and (cl.clans[wolves].wk.by as Dictionary).is_empty(),
		"Monday: a new week, every clan back to 0")
	var paid_w := eco.rewards.filter(func(r): return str(r[1]) == "2026-10-19")
	var want := []
	for pid in by:
		if int(by[pid]) >= Eco.CLAN_CHEST_MIN:
			want.append(ids[P.find(pid)])
	var accts_paid: Array = paid_w.map(func(r): return str(r[0]))
	accts_paid.sort()
	want.sort()
	check(accts_paid == want and not accts_paid.has(ids[3]), "the members with %d+ points were paid (Dan's 6 weren't enough): %d" % [Eco.CLAN_CHEST_MIN, accts_paid.size()])
	var r0: Dictionary = paid_w[0][2] if not paid_w.is_empty() else {}
	check(str(r0.get("chest", "")) == Eco.clan_chest_of(tier) and int(r0.get("gems", 0)) == 100 and int(r0.get("rank", 0)) == 1 and str(r0.get("tag", "")) == "WOLF",
		"each got the %s and the League's first place gems (100): %s" % [Eco.clan_chest_of(tier), str(r0)])
	check(not got(1, "eco").is_empty(), "their phones are told to fetch their accounts")
	check(str(cl.clans[wolves].fr) == "gold" and str(cl.clans[old].fr) == "silver" and str(cl.summary(cl.clans[wolves]).get("fr", "")) == "gold",
		"the podium's frames: the Wolves gold, Bob's clan silver")
	var bob_paid := eco.rewards.filter(func(r): return str(r[0]) == ids[1])
	check(bob_paid.is_empty(), "Bob's 5 points were short of %d: no chest, no gems" % Eco.CLAN_CHEST_MIN)
	var lastw: Dictionary = cl.clans[wolves].last
	check(int(lastw.get("pts", 0)) == wolf_pts and int(lastw.get("rank", 0)) == 1 and int(lastw.get("paid", 0)) == want.size()
		and str(lastw.get("week", "")) == "2026-10-19", "the clan remembers last week: %s" % str(lastw))
	check(chat_lines(1).any(func(m): return str(m.get("x", "")).begins_with("Last week:")), "a line in its chat says so")
	check(cl.league_last.size() == 2 and str(cl.league_last[0].tag) == "WOLF", "last week's podium for the League window")
	s.tick(Clans.PUSH_EVERY + 0.1)
	check(not clan(1).get("last", {}).is_empty() and int(clan(1).get("pts", -1)) == 0, "the members' state: last week, 0 points now")

	# ---------------- clans.json ----------------
	cl.add_match(ids[0], {"kills":1}, true, false, [])
	s.handle(5, {"k":"clan_ask", "h":"stormcaller"})
	cl.save_now()
	var again = Clans.new(dir, s)
	check(str(again.week) == "2026-10-26" and int(again.clans[wolves].wk.pts) == 11 and Eco.crest_code(again.clans[wolves].crest) == "4.1.2"
		and int(again.clans[wolves].xp) == int(cl.clans[wolves].xp) and str(again.clans[wolves].fr) == "gold"
		and (again.clans[wolves].ask as Dictionary).has(E) and int(again.asked_at.get(E, 0)) > 0 and again.league_last.size() == 2,
		"clans.json read back: the week, points, crest, XP, frame, requests, the podium")
	var n_before := eco.rewards.size()
	cl._settle("2026-10-19")
	check(eco.rewards.size() == n_before, "a week is paid once (the accounts refuse a second time)")

	# ---------------- the accounts (server/eco_accounts.gd, Profile) ----------------
	check(not Profile.OPS.has("grant_clan_reward") and not Profile.OPS.has("give_shard") and not Profile.OPS.has("receive_shard"),
		"the clan's grants aren't ops a phone can send")
	var tmp := OS.get_user_data_dir().path_join("clanweek-srv-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	var acc = Accounts.new(tmp)
	var a1: Dictionary = acc.handle({"t":"eco", "new":true})
	var a2: Dictionary = acc.handle({"t":"eco", "new":true})
	var pa1 = acc._load(str(a1.acct)).p
	var pb1 = acc._load(str(a2.acct)).p
	var gems0 := int(pa1.d.gems)
	var slots0: int = (pa1.d.chests.slots as Array).size()
	check(acc.grant_clan_reward(str(a1.acct), "2026-10-19", {"chest":"gold", "gems":60, "rank":2, "tier":3, "clan":"Iron Wolves", "tag":"WOLF", "pts":640})
		and not acc.grant_clan_reward(str(a1.acct), "2026-10-19", {"chest":"gold", "gems":60}),
		"a week's clan reward is paid once")
	check(int(pa1.d.gems) == gems0 + 60 and (pa1.d.chests.slots as Array).size() == slots0 + 1 and str(pa1.d.chests.slots[-1].kind) == "gold"
		and str(pa1.d.clan_rewards[0].week) == "2026-10-19" and int(pa1.d.clan_rewards[0].rank) == 2 and str(pa1.d.clan_rewards[0].tag) == "WOLF",
		"...the gems, the Gold Chest in a slot, and a record for the phone's notice")
	pa1.d.shards = ["golem", "golem"]
	pa1.save()
	var gold0 := int(pa1.d.gold)
	var gr: Dictionary = acc.give_shard(str(a1.acct), str(a2.acct), "golem")
	check(bool(gr.get("ok", false)) and int(gr.gold) == Eco.shard_melt_gold("golem", pa1.now()) and int(pa1.d.gold) == gold0 + int(gr.gold)
		and pa1.shards_of("golem") == 1 and pb1.shards_of("golem") == 1, "a shard given: the giver's melt gold (%d), the asker's shard" % int(gr.get("gold", 0)))
	check(str(acc.give_shard(str(a1.acct), str(a2.acct), "druid").get("error", "")) == "no_shard", "no shard of that hero: nothing given")
	var a3: Dictionary = acc.handle({"t":"eco", "new":true})
	var pc1 = acc._load(str(a3.acct)).p
	check(pb1.giftable_shards("golem") == 0 and (pb1.d.gift_shards as Array) == ["golem"]
		and str(acc.give_shard(str(a2.acct), str(a3.acct), "golem").get("error", "")) == "gifted" and pc1.shards_of("golem") == 0,
		"a shard a clanmate gave isn't given on (passed round it would pay its melt gold every time)")
	pb1.d.gold = 0
	check(bool(pb1.melt_shard("golem").ok) and pb1.shards_of("golem") == 0 and (pb1.d.gift_shards as Array).is_empty(), "...it can be melted (or used): the gift goes with it")
	pb1.d.shards = ["golem"]
	pb1.d.gift_shards = []
	pb1.save()
	pb1.d.heroes = ["golem"]
	pb1.save()
	check(str(acc.give_shard(str(a1.acct), str(a2.acct), "golem").get("error", "")) == "owned" and pa1.shards_of("golem") == 1,
		"the asker owns the hero now: refused, the shard stays")
	check((acc.heroes_of(str(a2.acct)).get("own", []) as Array).has("golem"), "heroes_of: the heroes an account owns")
	var back2: Dictionary = acc.handle({"t":"eco", "acct":str(a2.acct), "key":str(a2.key), "ops":[]})
	check((back2.profile.shards as Array).has("golem"), "...and the asker's phone gets the shard with its account")

	for fn in ["clans.json", "social.json", "chat.json"]:
		DirAccess.remove_absolute(dir.path_join(fn))
	DirAccess.remove_absolute(dir)
	if fails.is_empty():
		print("CLAN_WEEK_PASS")
	else:
		print("CLAN_WEEK_FAIL %d: %s" % [fails.size(), str(fails)])
	quit(0 if fails.is_empty() else 1)
