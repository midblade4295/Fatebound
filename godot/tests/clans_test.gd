extends SceneTree
# 0.31.134 (Crown War step 1): server/clans.gd through server/social.gd's own socket handling (fake sockets, a stand-in
# for the accounts with gold and levels). Starting a clan (its cost taken, name/tag/house rules, unique names and tags,
# the word filter); finding clans; joining an open clan, asking to join one by request (level rule, officers answer),
# invites (past the level and the mode; blocked players never get them); clan chat to members only, with the tag on
# every card and line; roles (officers, kicks, the leader's powers); leaving and its 24-hour wait; a leader leaving or
# away 14 days handing the clan on; disbanding; a full clan; an account deleted; clans.json read back; the
# leaderboard's tag. 0.31.148 (Kevin: "Make it cost 5000 gold and make a default clan for each faction"): 5,000 gold; the
# house clans (there from the start, free and open, nobody leading them, moving out of them by joining or starting a
# players' clan, no wait on leaving them, never ended, kept in clans.json, a players' clan's tag left alone).
#   godot --headless --path godot -s res://tests/clans_test.gd
const Social = preload("res://server/social.gd")
const Clans = preload("res://server/clans.gd")
const Leaderboard = preload("res://server/leaderboard.gd")

var fails: Array = []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

class FakeEco:
	var accts := {}
	func add(id: String, name: String, gold: int, lv: int) -> void:
		accts[id] = {"name":name, "gold":gold, "lv":lv}
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

func clear() -> void:
	inbox = {}

func pids(list: Array) -> Array:
	return list.map(func(c): return str(c.get("pid", "")))

func players_clans(cl) -> Array:
	# the players' clans (0.31.148: the house clans are always there too)
	return cl.clans.keys().filter(func(id): return not bool(cl.clans[id].get("hc", false)))

func _init() -> void:
	var dir := OS.get_user_data_dir().path_join("clantest-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(dir)
	var eco := FakeEco.new()
	var names := ["Alice", "Bob", "Cara", "Dan", "Eve", "Finn", "Gus"]
	var golds := [12000, 500, 20000, 0, 0, 0, 0]
	var lvls := [10, 3, 1, 20, 2, 6, 4]
	var ids := []
	for i in names.size():
		var id := "%020x" % (i + 1)
		eco.add(id, names[i], golds[i], lvls[i])
		ids.append(id)
	var T0 := 1791000000
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
		check(s.hello(i + 1, {"k":"hi", "acct":ids[i], "key":"k".repeat(64)}), "%s in" % names[i])
		P.append(Social.pid_of(ids[i]))
	var A: String = P[0]
	var B: String = P[1]
	var C: String = P[2]
	var D: String = P[3]
	var E: String = P[4]
	var F: String = P[5]
	var G: String = P[6]
	check(int(last(1, "me").get("clans", 0)) == 1 and not last(1, "clan").is_empty() and clan(1).is_empty(),
		"hello says the server has clans, and sends the (empty) clan state")
	check(int(last(1, "clan").get("cost", 0)) == Clans.COST_GOLD and Clans.COST_GOLD == 5000 and Clans.MAX_MEMBERS == 30, "a clan costs 5,000 gold, 30 members")
	var hcs: Array = last(1, "clan").get("hcs", [])
	var hc_ok := hcs.size() == 3
	for h in hcs:
		hc_ok = hc_ok and bool(h.get("hc", false)) and str(h.join) == "open" and int(h.min_lv) == 1 and int(h.n) == 0 and int(h.max) == Clans.HOUSE_CLAN_MAX
	check(hc_ok and hcs.map(func(h): return str(h.tag)) == ["LION", "STAG", "RAVN"] and str(hcs[0].name) == "The Lion Guard" and str(hcs[0].house) == "lions",
		"the three house clans are there from the start, in every clan state: %s" % str(hcs.map(func(h): return str(h.name))))

	# ---------------- starting a clan ----------------
	clear()
	s.handle(2, {"k":"clan_new", "name":"Poor Pals", "tag":"POOR", "house":"lions"})
	check(not bool(last(2, "clan_made").get("ok", true)) and str(last(2, "clan_made").why) == "gold" and players_clans(cl).is_empty() and int(eco.accts[ids[1]].gold) == 500,
		"500 gold isn't enough: refused, nothing taken")
	var bad := [[{"name":"Fuck Squad", "tag":"FSQ", "house":"lions"}, "name"], [{"name":"Ok Name", "tag":"AB", "house":"lions"}, "tag"],
		[{"name":"Ok Name", "tag":"FUK", "house":"lions"}, "tag"], [{"name":"Ok Name", "tag":"OKN", "house":"dragons"}, "house"],
		[{"name":"No<html>", "tag":"OKN", "house":"lions"}, "name"], [{"name":"ab", "tag":"OKN", "house":"lions"}, "name"],
		[{"name":"Ok Name", "tag":"O K", "house":"lions"}, "tag"]]
	for b in bad:
		clear()
		var m: Dictionary = b[0].duplicate()
		m["k"] = "clan_new"
		s.handle(1, m)
		check(str(last(1, "clan_made").get("why", "")) == str(b[1]) and players_clans(cl).is_empty(), "refused (%s): %s" % [b[1], str(b[0])])
	check(int(eco.accts[ids[0]].gold) == 12000, "refusals take no gold")
	clear()
	s.handle(1, {"k":"clan_new", "name":"  Iron   Wolves ", "tag":"wolf", "house":"stags", "join":"open", "min_lv":1})
	var mine := clan(1)
	check(bool(last(1, "clan_made").get("ok", false)) and str(mine.get("name", "")) == "Iron Wolves" and str(mine.get("tag", "")) == "WOLF"
		and str(mine.get("house", "")) == "stags" and str(mine.get("role", "")) == "leader" and int(mine.get("n", 0)) == 1,
		"Alice starts [WOLF] Iron Wolves of House Stags and leads it: %s" % str(mine))
	check(int(eco.accts[ids[0]].gold) == 7000, "5,000 gold taken from her account (12,000 -> %d)" % int(eco.accts[ids[0]].gold))
	var hist: Array = last(1, "hist").get("list", [])
	check(str(last(1, "hist").get("ch", "")) == "clan" and not hist.is_empty() and str(hist[0].get("x", "")).contains("founded"), "the clan chat opens with a founding line")
	check(str(last(1, "me").get("ct", "x")) == "" or s.tag_of(A) == "WOLF", "her tag is WOLF")
	clear()
	s.handle(3, {"k":"clan_new", "name":"iron-wolves", "tag":"IWX", "house":"lions"})
	check(str(last(3, "clan_made").get("why", "")) == "taken" and int(eco.accts[ids[2]].gold) == 20000, "the same name (any case, spaces, dashes): taken, nothing paid")
	clear()
	s.handle(3, {"k":"clan_new", "name":"Night Owls", "tag":"Wolf", "house":"lions"})
	check(str(last(3, "clan_made").get("why", "")) == "taken", "the same tag: taken")
	clear()
	s.handle(1, {"k":"clan_new", "name":"Second Clan", "tag":"SEC", "house":"lions"})
	check(str(last(1, "clan_made").get("why", "")) == "in_clan", "one clan at a time")
	var wolves: String = cl.clan_of(A)

	s.tick(Clans.MSG_WINDOW + 1.0)
	# ---------------- finding and joining an open clan ----------------
	clear()
	s.handle(2, {"k":"clan_find", "q":"wol"})
	var found: Array = last(2, "clans").get("list", [])
	check(found.size() == 1 and str(found[0].tag) == "WOLF" and int(found[0].n) == 1 and str(found[0].lead) == "Alice", "finding \"wol\": the Wolves, 1 member, led by Alice")
	s.handle(2, {"k":"clan_find", "q":"", "house":"lions"})
	var lions_found: Array = last(2, "clans").get("list", [])
	check(lions_found.size() == 1 and bool(lions_found[0].get("hc", false)), "no players' clans of House Lions yet (its house clan only)")
	clear()
	s.handle(2, {"k":"clan_info", "id":wolves})
	var info: Dictionary = last(2, "clan_info").get("c", {})
	check(str(info.get("name", "")) == "Iron Wolves" and (info.get("members", []) as Array).size() == 1 and not (info.members[0] as Dictionary).has("st"),
		"a clan's card for an outsider: its members, without their online status")
	clear()
	s.handle(2, {"k":"clan_join", "id":wolves})
	check(cl.clan_of(B) == wolves and int(clan(2).get("n", 0)) == 2 and int(clan(1).get("n", 0)) == 2 and str(clan(2).role) == "member",
		"Bob joins the open clan; both see 2 members")
	check(notes(2).contains("Welcome"), "Bob is welcomed")
	var bob_card: Dictionary = {}
	for m in clan(1).get("members", []):
		if str(m.pid) == B:
			bob_card = m
	check(str(bob_card.get("ct", "")) == "WOLF" and str(bob_card.get("st", "")) == "online", "members see each other's tag and status")

	# ---------------- clan chat ----------------
	clear()
	s.handle(2, {"k":"chat", "ch":"clan", "x":"hi wolves"})
	var line: Dictionary = last(1, "chat").get("m", {})
	check(str(line.get("x", "")) == "hi wolves" and str(line.get("ch", "")) == "clan" and str(line.get("ct", "")) == "WOLF" and got(3, "chat").is_empty(),
		"clan chat reaches members only, with the tag")
	s.tick(2.0)
	clear()
	s.handle(3, {"k":"chat", "ch":"clan", "x":"let me in"})
	check(got(1, "chat").is_empty() and notes(3).contains("not in a clan"), "no clan: no clan chat")
	s.tick(2.0)
	clear()
	s.handle(2, {"k":"chat", "ch":"global", "x":"hello world"})
	check(str(last(3, "chat").get("m", {}).get("ct", "")) == "WOLF", "global lines carry the tag too")

	# ---------------- request mode, levels, officers answer ----------------
	clear()
	s.handle(2, {"k":"clan_set", "join":"invite"})
	check(str(cl.clans[wolves].join) == "open", "a member can't change the settings")
	s.handle(1, {"k":"clan_set", "join":"request", "min_lv":5})
	check(str(cl.clans[wolves].join) == "request" and int(cl.clans[wolves].min_lv) == 5 and str(clan(2).get("join", "")) == "request", "the leader sets: by request, level 5")
	clear()
	s.handle(5, {"k":"clan_join", "id":wolves})
	check(cl.clan_of(E) == "" and notes(5).contains("level 5") and not (cl.clans[wolves].req as Dictionary).has(E), "Eve (level 2) can't ask yet")
	clear()
	s.handle(4, {"k":"clan_join", "id":wolves})
	check(cl.clan_of(D) == "" and (cl.clans[wolves].req as Dictionary).has(D) and notes(4).contains("Request sent"), "Dan (level 20) asks to join")
	check(pids(clan(1).get("req", [])).has(D) and not (clan(2) as Dictionary).has("req") and (last(4, "clan").get("asked", []) as Array).has(wolves),
		"the leader sees the request (members don't); Dan's state shows it asked")
	clear()
	s.handle(2, {"k":"clan_accept", "pid":D})
	check(cl.clan_of(D) == "", "a member can't accept")
	s.handle(1, {"k":"clan_accept", "pid":D})
	check(cl.clan_of(D) == wolves and int(clan(4).get("n", 0)) == 3 and (cl.clans[wolves].req as Dictionary).is_empty(), "the leader accepts Dan")
	# --- invites
	clear()
	s.handle(2, {"k":"clan_invite", "pid":E})
	check(got(5, "clan_inv").is_empty() and notes(2).contains("leader and officers"), "a member can't invite")
	s.handle(1, {"k":"clan_invite", "pid":E})
	check(str(last(5, "clan_inv").get("c", {}).get("tag", "")) == "WOLF" and str(last(5, "clan_inv").get("by", {}).get("n", "")) == "Alice"
		and (last(5, "clan").get("inv", []) as Array).size() == 1, "Alice invites Eve: Eve gets it, and it's in her state")
	clear()
	s.handle(5, {"k":"clan_join", "id":wolves})
	check(cl.clan_of(E) == wolves and not cl.invites.has(E), "an invite lets Eve in past the level rule and the request mode")
	# --- a blocked inviter
	s.handle(6, {"k":"block", "pid":A})
	clear()
	s.handle(1, {"k":"clan_invite", "pid":F})
	check(got(6, "clan_inv").is_empty() and not cl.invites.has(F) and notes(1).contains("Invited"), "a player who blocked you never gets your invite (it looks sent)")

	s.tick(Clans.MSG_WINDOW + 1.0)
	# ---------------- roles ----------------
	clear()
	s.handle(2, {"k":"clan_role", "pid":D, "role":"officer"})
	check(cl.role_of(D) == "member", "only the leader names officers")
	s.handle(1, {"k":"clan_role", "pid":B, "role":"officer"})
	check(cl.role_of(B) == "officer" and str(clan(2).get("role", "")) == "officer" and pids(clan(2).get("req", [])) == [], "Bob is an officer (and sees requests now)")
	clear()
	s.handle(2, {"k":"clan_kick", "pid":D})
	check(cl.clan_of(D) == "" and notes(4).contains("removed") and clan(4).is_empty() and int(last(4, "clan").get("cool", 0)) == T0 + Clans.COOLDOWN,
		"officer Bob removes Dan; Dan waits 24 hours")
	clear()
	s.handle(4, {"k":"clan_new", "name":"Dans Den", "tag":"DAN", "house":"ravens"})
	check(str(last(4, "clan_made").get("why", "")) == "cool", "Dan can't start a clan for 24 hours")
	s.handle(1, {"k":"clan_role", "pid":E, "role":"officer"})
	clear()
	s.handle(2, {"k":"clan_kick", "pid":E})
	check(cl.clan_of(E) == wolves and notes(2).contains("Only the leader"), "an officer can't remove another officer")
	s.handle(1, {"k":"clan_role", "pid":E, "role":"member"})
	check(cl.role_of(E) == "member", "the leader makes Eve a member again")
	clear()
	s.handle(1, {"k":"clan_kick", "pid":A})
	check(cl.clan_of(A) == wolves, "the leader can't remove themself")

	# ---------------- the leader hands over, leaves ----------------
	clear()
	s.handle(1, {"k":"clan_lead", "pid":E})
	check(cl.role_of(E) == "leader" and cl.role_of(A) == "officer", "Alice hands the clan to Eve and stays as an officer")
	s.handle(5, {"k":"clan_lead", "pid":A})
	clear()
	s.handle(1, {"k":"clan_leave"})
	check(cl.clan_of(A) == "" and cl.role_of(B) == "leader" and int(clan(2).get("n", 0)) == 2, "the leader leaves: officer Bob leads (2 left)")
	check(int(last(1, "clan").get("cool", 0)) == T0 + Clans.COOLDOWN and s.tag_of(A) == "", "Alice waits 24 hours and has no tag")
	s.now_override = T0 + Clans.COOLDOWN + 5
	cl.sweep()
	clear()
	s.handle(1, {"k":"clan_join", "id":wolves})
	check(cl.clan_of(A) == "" and (cl.clans[wolves].req as Dictionary).has(A), "a day later Alice can ask again")
	s.handle(1, {"k":"clan_unreq", "id":wolves})
	check(not (cl.clans[wolves].req as Dictionary).has(A), "and take the request back")

	s.tick(Clans.MSG_WINDOW + 1.0)
	# ---------------- disbanding ----------------
	clear()
	s.handle(5, {"k":"clan_disband"})
	check(cl.clans.has(wolves), "only the leader can disband")
	s.handle(2, {"k":"clan_disband"})
	check(not cl.clans.has(wolves) and cl.clan_of(B) == "" and cl.clan_of(E) == "" and clan(5).is_empty() and notes(5).contains("disbanded")
		and not last(5, "clan").has("cool") and not s.hist.has("c:" + wolves), "Bob disbands: everyone's out, told, no waiting, the chat gone")

	s.tick(Clans.MSG_WINDOW + 1.0)
	# ---------------- a leader away 14 days ----------------
	clear()
	s.handle(3, {"k":"clan_new", "name":"Night Owls", "tag":"OWL", "house":"ravens", "join":"open"})
	var owls: String = cl.clan_of(C)
	check(owls != "" and int(eco.accts[ids[2]].gold) == 15000, "Cara starts [OWL] Night Owls (House Ravens)")
	s.handle(6, {"k":"clan_join", "id":owls})
	s.handle(7, {"k":"clan_join", "id":owls})
	s.handle(3, {"k":"clan_role", "pid":F, "role":"officer"})
	s.drop(3)                                          # Cara goes away
	s.now_override = T0 + Clans.COOLDOWN + 3 * 86400
	s.drop(6)                                          # Finn (officer) last seen 3 days later
	s.now_override = T0 + Clans.COOLDOWN + 5 + Clans.LEADER_AWAY + 3600
	cl.sweep()
	check(cl.role_of(F) == "leader" and cl.role_of(C) == "officer", "Cara away 14 days: officer Finn (seen since) leads; Cara stays an officer")
	check(str((s.hist.get("c:" + owls, []) as Array).back().get("x", "")).contains("away"), "the clan chat says why")

	s.tick(Clans.MSG_WINDOW + 1.0)
	# ---------------- a full clan ----------------
	var extra := []
	for i in Clans.MAX_MEMBERS:
		var id := "%020x" % (100 + i)
		eco.add(id, "P%d" % i, 0, 1)
		s.hello(100 + i, {"k":"hi", "acct":id, "key":"k".repeat(64)})
		extra.append(Social.pid_of(id))
	for i in Clans.MAX_MEMBERS:
		s.handle(100 + i, {"k":"clan_join", "id":owls})
	check((cl.clans[owls].members as Dictionary).size() == Clans.MAX_MEMBERS and notes(100 + Clans.MAX_MEMBERS - 1).contains("full"),
		"30 members at most (the rest are told it's full)")

	# ---------------- the tag on cards and the leaderboard ----------------
	s.handle(7, {"k":"add", "pid":B})
	s.handle(2, {"k":"add", "pid":G})
	var fcards: Array = last(2, "friends").get("friends", [])
	check(not fcards.is_empty() and str(fcards[0].get("ct", "")) == "OWL", "a friend's card carries their clan tag")
	var lb = Leaderboard.new(dir, T0)
	lb.tag_fn = func(acct: String) -> String: return cl.tag_of_acct(acct)
	lb.add_match(ids[6], "Gus", "", {"kills":3, "rescues":1, "gate_dmg":0, "gathered":0, "fed":0}, true)
	lb.add_match(ids[1], "Bob", "", {"kills":1, "rescues":0, "gate_dmg":0, "gathered":0, "fed":0}, false)
	var ans: Dictionary = lb.answer(ids[6], [])
	check(str(ans.top[0].get("ct", "")) == "OWL" and not (ans.top[1] as Dictionary).has("ct"), "leaderboard rows carry the tag (none without a clan)")

	# ---------------- an account deleted ----------------
	s.forget(ids[6])
	check(not (cl.clans[owls].members as Dictionary).has(G) and cl.clan_of(G) == "", "a deleted account leaves its clan")

	# ---------------- review fixes: the last one out, invites again, blocking, asking again, too many messages ----------------
	eco.add("%020x" % 200, "Hana", 30000, 10)
	eco.add("%020x" % 201, "Ivo", 0, 10)
	s.hello(200, {"k":"hi", "acct":"%020x" % 200, "key":"k".repeat(64)})
	s.hello(201, {"k":"hi", "acct":"%020x" % 201, "key":"k".repeat(64)})
	var H := Social.pid_of("%020x" % 200)
	var I := Social.pid_of("%020x" % 201)
	s.tick(Clans.MSG_WINDOW + 1.0)
	s.handle(200, {"k":"clan_new", "name":"Solo Act", "tag":"SOLO", "house":"lions"})
	s.handle(200, {"k":"clan_leave"})
	check(players_clans(cl).size() == 1 and not cl.cool.has(H) and int(eco.accts["%020x" % 200].gold) == 25000, "the last one out ends the clan with no wait (like disbanding)")
	s.handle(200, {"k":"clan_new", "name":"Second Act", "tag":"SEC", "house":"lions", "join":"request"})
	var sec: String = cl.clan_of(H)
	check(sec != "" and FileAccess.file_exists(dir.path_join("clans.json")) and FileAccess.get_file_as_string(dir.path_join("clans.json")).contains("Second Act"),
		"a new clan is on disk at once (its gold is gone already)")
	clear()
	s.handle(201, {"k":"clan_join", "id":sec})
	s.handle(201, {"k":"clan_unreq", "id":sec})
	s.handle(201, {"k":"clan_join", "id":sec})
	check(got(200, "note").filter(func(m): return str(m.get("x", "")).contains("asked to join")).size() == 1 and (cl.clans[sec].req as Dictionary).has(I),
		"asking, taking it back and asking again pops up for the officers once")
	s.handle(201, {"k":"clan_unreq", "id":sec})
	clear()
	s.handle(200, {"k":"clan_invite", "pid":I})
	s.handle(200, {"k":"clan_invite", "pid":I})
	check(got(201, "clan_inv").size() == 1 and (cl.invites.get(I, {}) as Dictionary).has(sec), "inviting twice sends one invite")
	clear()
	s.handle(201, {"k":"block", "pid":H})
	check(not cl.invites.has(I) and (last(201, "clan").get("inv", [1]) as Array).is_empty(), "blocking the officer takes their invite away")
	s.tick(Clans.MSG_WINDOW + 1.0)
	clear()
	for i in Clans.MSG_BURST + 3:
		s.handle(201, {"k":"clan_find", "q":""})
	check(got(201, "clans").size() == Clans.MSG_BURST and notes(201).contains("Slow down"), "more than %d clan messages in %d s: slowed down" % [Clans.MSG_BURST, int(Clans.MSG_WINDOW)])
	s.handle(200, {"k":"clan_disband"})
	s.tick(Clans.MSG_WINDOW + 1.0)

	# ---------------- the house clans (0.31.148) ----------------
	var hl: String = Clans.HOUSE_CLANS.lions.id
	var hs: String = Clans.HOUSE_CLANS.stags.id
	clear()
	s.handle(201, {"k":"clan_join", "id":hl})
	check(cl.clan_of(I) == hl and str(clan(201).get("role", "")) == "member" and bool(clan(201).get("hc", false)) and notes(201).contains("Welcome")
		and s.tag_of(I) == "LION", "Ivo (no gold) joins The Lion Guard for free: a member, tagged [LION]")
	check(not s.hist.has("c:" + hl) or (s.hist["c:" + hl] as Array).is_empty(), "no join line in a house clan's chat")
	clear()
	s.handle(201, {"k":"clan_join", "id":hs})
	check(cl.clan_of(I) == hs and not (cl.clans[hl].members as Dictionary).has(I) and cl.clans.has(hl), "joining another house's clan moves him (the Lion Guard stays, empty)")
	clear()
	s.handle(201, {"k":"clan_leave"})
	check(cl.clan_of(I) == "" and not cl.cool.has(I) and not last(201, "clan").has("cool"), "leaving a house clan: no wait")
	s.handle(201, {"k":"clan_join", "id":hl})
	clear()
	s.handle(201, {"k":"clan_kick", "pid":I})
	s.handle(201, {"k":"clan_set", "join":"invite"})
	s.handle(201, {"k":"clan_disband"})
	check(cl.clan_of(I) == hl and str(cl.clans[hl].join) == "open" and cl.clans.has(hl) and cl.role_of(I) == "member", "nobody runs a house clan: no settings, no disbanding")
	s.tick(Clans.MSG_WINDOW + 1.0)
	clear()
	s.handle(200, {"k":"clan_new", "name":"Hana Gang", "tag":"HANA", "house":"stags", "join":"open"})
	var hana: String = cl.clan_of(H)
	clear()
	s.handle(201, {"k":"clan_join", "id":hana})
	check(cl.clan_of(I) == hana and not (cl.clans[hl].members as Dictionary).has(I) and not cl.cool.has(I), "joining a players' clan moves him out of the house clan (no wait)")
	s.handle(201, {"k":"clan_leave"})
	check(int(cl.cool.get(I, 0)) > 0, "(leaving a players' clan still means the wait)")
	clear()
	s.handle(201, {"k":"clan_join", "id":hl})
	check(cl.clan_of(I) == hl, "...but the wait doesn't keep him out of his house's clan")
	s.handle(200, {"k":"clan_leave"})
	s.handle(200, {"k":"clan_join", "id":hs})
	check(cl.clan_of(H) == hs, "Hana joins The Stag Guard")
	s.tick(Clans.MSG_WINDOW + 1.0)
	clear()
	s.now_override = int(s.now_override) + Clans.COOLDOWN + 5
	cl.sweep()
	s.handle(200, {"k":"clan_new", "name":"Hana Again", "tag":"HNA", "house":"stags", "join":"open"})
	var hana2: String = cl.clan_of(H)
	check(hana2 != "" and hana2 != hs and not (cl.clans[hs].members as Dictionary).has(H) and int(eco.accts["%020x" % 200].gold) == 10000,
		"starting a clan moves her out of the house clan (5,000 gold: 15,000 -> %d)" % int(eco.accts["%020x" % 200].gold))
	cl.sweep()                                         # (no leader ever seen: a players' clan would be handed on here)
	check(str(cl.clans[hl].leader) == "" and cl.role_of(I) == "member", "a house clan is never handed to anyone")
	s.handle(200, {"k":"clan_disband"})
	s.tick(Clans.MSG_WINDOW + 1.0)

	# ---------------- clans.json ----------------
	s.hello(3, {"k":"hi", "acct":ids[2], "key":"k".repeat(64)})   # (Cara is back, an officer: an invite to keep)
	s.handle(3, {"k":"clan_invite", "pid":A})
	s.handle(100, {"k":"clan_leave"})                         # (and a cooldown to keep)
	cl.save_now()
	var again = Clans.new(dir, s)
	check(players_clans(again).size() == 1 and again.clan_of(F) == owls and again.role_of(F) == "leader" and again.tag_of(C) == "OWL"
		and (again.clans[owls].members as Dictionary).size() == (cl.clans[owls].members as Dictionary).size()
		and (again.invites.get(A, {}) as Dictionary).has(owls) and int(again.cool.get(str(extra[0]), 0)) == int(s.now_override) + Clans.COOLDOWN,
		"clans.json read back: clans, leaders, members, invites, cooldowns")
	check(again.is_house(Clans.HOUSE_CLANS.lions.id) and again.clan_of(I) == Clans.HOUSE_CLANS.lions.id and again.is_house(Clans.HOUSE_CLANS.ravens.id)
		and (again.clans[Clans.HOUSE_CLANS.ravens.id].members as Dictionary).is_empty(), "...the house clans too (an empty one kept)")
	# a server whose players took [LION] before the house clans came: the Lion Guard takes the next tag
	var dir2 := OS.get_user_data_dir().path_join("clantest2-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(dir2)
	var f := FileAccess.open(dir2.path_join("clans.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"v":1, "clans":{"cx": {"id":"cx", "name":"Lion Hearts", "tag":"LION", "house":"lions", "join":"open", "min_lv":1,
		"leader":A, "officers":[], "members":{A: T0}, "req":{}, "created":T0}}, "inv":{}, "cool":{}}))
	f.close()
	var older = Clans.new(dir2, s)
	check(str(older.clans.cx.tag) == "LION" and str(older.clans[Clans.HOUSE_CLANS.lions.id].tag) == "LNG", "a players' [LION] kept: the Lion Guard is [LNG]")
	DirAccess.remove_absolute(dir2.path_join("clans.json"))
	DirAccess.remove_absolute(dir2)

	DirAccess.remove_absolute(dir.path_join("clans.json"))
	DirAccess.remove_absolute(dir.path_join("social.json"))
	DirAccess.remove_absolute(dir.path_join("leaderboard.json"))
	DirAccess.remove_absolute(dir)
	if fails.is_empty():
		print("CLANS_PASS")
	else:
		print("CLANS_FAIL %d: %s" % [fails.size(), str(fails)])
	quit(0 if fails.is_empty() else 1)
