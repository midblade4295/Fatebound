extends SceneTree
# 0.31.135 (Crown War step 2): server/world.gd through server/social.gd and server/clans.gd (fake sockets, a stand-in
# for the accounts). The shared map (18 places, the links, every territory reachable, homes never attackable); who may
# attack what (linked to the house's land or home); starting a battle (a room from siege_server, or "busy"; one battle a
# territory; the same house joins it; the clan called; the holders alarmed); sides (attackers, holders, nobody else;
# no defenders for land nobody holds); attempts (5 a day, the starter's spent at once, the others' when seated, a new
# day starts again); one battle on at a time for a player, two for a clan; the points (crowns x 50, a loss -100, a
# quitter -100, a battle every player left is lost) and taking a territory (500 when nobody holds it, 1000 when a house
# does); the map each phone gets; a week ending (the house with the most land wins it, the map is free again; a battle
# still on then counts for nothing); world.json (a damaged one doesn't stop the saves); a malformed "call".
#   godot --headless --path godot -s res://tests/world_test.gd
const Social = preload("res://server/social.gd")
const Clans = preload("res://server/clans.gd")
const World = preload("res://server/world.gd")
const Map = preload("res://scripts/meta/war_map.gd")

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

var inbox := {}

func got(cid: int, k: String) -> Array:
	return (inbox.get(cid, []) as Array).filter(func(m): return str(m.get("k", "")) == k)

func last(cid: int, k: String) -> Dictionary:
	var l := got(cid, k)
	return l[l.size() - 1] if not l.is_empty() else {}

func clear() -> void:
	inbox = {}

func _init() -> void:
	# ---------------- the map ----------------
	var terr := Map.territories()
	check(Map.T.size() == 18 and terr.size() == 15 and Map.HOMES.size() == 3, "18 places: 15 territories and 3 homes")
	var bad_links := Map.LINKS.filter(func(l): return not Map.T.has(l[0]) or not Map.T.has(l[1]))
	check(bad_links.is_empty() and Map.LINKS.size() == 30, "30 links, all between real places")
	var seen := {"home_lions": true}
	var todo := ["home_lions"]
	while not todo.is_empty():
		var at: String = todo.pop_back()
		for n in Map.neighbours(at):
			if not seen.has(n):
				seen[n] = true
				todo.append(n)
	check(seen.size() == 18, "every place is reachable from every other")
	check(Map.neighbours("home_lions").size() == 2 and Map.neighbours("home_stags").size() == 2 and Map.neighbours("home_ravens").size() == 2,
		"each home has two ways out")
	check(Map.points(3, true) == 150 and Map.points(1, true) == 50 and Map.points(2, false) == 0 and Map.points(0, false) == -100,
		"points: 50 a crown, -100 for a loss (a win always counts, a loss never helps)")

	# ---------------- players, clans ----------------
	var dir := OS.get_user_data_dir().path_join("worldtest-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(dir)
	var eco := FakeEco.new()
	var who := [["Alice", 20000], ["Bob", 0], ["Sam", 20000], ["Rae", 20000], ["Lena", 20000], ["Tom", 0], ["Cara", 0]]
	var ids := []
	for i in who.size():
		var id := "%020x" % (i + 1)
		eco.add(id, str(who[i][0]), int(who[i][1]), 10)
		ids.append(id)
	var T0 := 1791763200 + 3600                        # Monday 2026-10-12 01:00 UTC
	var s = Social.new(dir, eco)
	s.now_override = T0
	s.send_fn = func(cid, msg):
		var l: Array = inbox.get(cid, [])
		l.append(msg)
		inbox[cid] = l
	s.clans = Clans.new(dir, s)
	var rooms := [7]                                   # what siege_server answers (0: busy)
	var w = World.new(dir, s)
	w.room_fn = func(_b) -> int: return int(rooms[0])
	s.world = w
	var P := []
	for i in ids.size():
		s.hello(i + 1, {"k":"hi", "acct":ids[i], "key":"k".repeat(64)})
		P.append(Social.pid_of(ids[i]))
	var A: String = P[0]
	var B: String = P[1]
	var S: String = P[2]
	var R: String = P[3]
	var L: String = P[4]
	var TM: String = P[5]
	var CR: String = P[6]
	check(int(last(1, "me").get("war", 0)) == 1, "hello says the server has the war map")
	# (0.31.148: the house clans hold [LION], [STAG] and [RAVN]; the players' clans here take other tags)
	s.handle(1, {"k":"clan_new", "name":"Lion Hearts", "tag":"LHRT", "house":"lions"})
	s.handle(2, {"k":"clan_join", "id":s.clans.clan_of(A)})
	s.handle(3, {"k":"clan_new", "name":"Stag Party", "tag":"STGP", "house":"stags"})
	s.handle(4, {"k":"clan_new", "name":"Raven Claw", "tag":"RVCL", "house":"ravens"})
	s.handle(5, {"k":"clan_new", "name":"Second Lions", "tag":"LNX", "house":"lions"})
	s.handle(7, {"k":"clan_join", "id":s.clans.clan_of(A)})
	var CA: String = s.clans.clan_of(A)
	var CS: String = s.clans.clan_of(S)
	check(CA != "" and s.clans.clan_of(B) == CA and CS != "" and s.clans.clan_of(R) != "" and s.clans.clan_of(L) != "", "four clans in three houses")

	# ---------------- the map on a phone ----------------
	clear()
	s.handle(1, {"k":"war_open"})
	var m: Dictionary = last(1, "war")
	check(not m.is_empty() and (m.terr as Dictionary).size() == 18 and str(m.house) == "lions" and int(m.att) == 5 and int(m.max) == 5,
		"WAR: 18 places, her house, 5 attempts")
	check(str(m.terr.home_stags.h) == "stags" and str(m.terr.mill.h) == "" and int(m.terr.mill.need) == 500, "homes held by their houses; the Mill free (500 to take)")
	check(str(m.terr.mill.why) == "" and str(m.terr.quarry.why) == "" and str(m.terr.lake.why).contains("linked") and str(m.terr.pass.why).contains("linked"),
		"Lions may attack the Mill and the Quarry (by their home), not the Lake or the Pass")
	check(str(m.week) == "2026-10-12" and int(m.ends) == 1791763200 + 7 * 86400, "this week runs Monday to Monday")
	s.handle(6, {"k":"war_go", "tid":"mill"})
	check(not bool(last(6, "war_go").get("ok", true)) and str(last(6, "war_go").why).contains("clan"), "no clan: no battle")
	clear()
	s.handle(1, {"k":"war_go", "tid":"lake"})
	check(not bool(last(1, "war_go").get("ok", true)) and str(last(1, "war_go").why).contains("linked"), "not linked: refused")
	s.handle(1, {"k":"war_go", "tid":"home_stags"})
	check(str(last(1, "war_go").get("why", "")).contains("Homes"), "a home: refused (King's Day comes later)")
	rooms[0] = 0
	s.handle(1, {"k":"war_go", "tid":"mill"})
	check(str(last(1, "war_go").get("why", "")).contains("busy") and w.battles.is_empty(), "every room busy: refused, no battle")
	rooms[0] = 7

	# ---------------- a battle ----------------
	clear()
	s.handle(1, {"k":"war_go", "tid":"mill", "call":true})
	var go: Dictionary = last(1, "war_go")
	var bid := str(go.get("bid", ""))
	check(bool(go.get("ok", false)) and bid != "" and str(go.side) == "att" and int(w.battles[bid].room) == 7, "Alice attacks the Mill: a battle in room 7")
	check(w.attempts_left(A) == 4 and (w.battles[bid].scorers as Dictionary).has(A), "starting it spent her attempt (4 left): it counts for her")
	check(str(last(2, "war_call").get("bid", "")) == bid and str(last(2, "war_call").get("by", "")) == "Alice" and got(1, "war_call").is_empty(),
		"her clanmate Bob is called to it (she isn't)")
	check(got(3, "war_alarm").is_empty(), "nobody holds the Mill: no alarm")
	clear()
	s.handle(2, {"k":"war_go", "tid":"mill"})
	check(str(last(2, "war_go").get("bid", "")) == bid and bool(last(2, "war_go").get("joined", false)) and w.battles.size() == 1, "Bob asking for the Mill joins her battle")
	s.handle(1, {"k":"war_go", "tid":"quarry"})
	check(str(last(1, "war_go").get("why", "")).contains("battle on already") and w.battles.size() == 1 and w.attempts_left(A) == 4,
		"Alice can't start a second battle while hers is on")
	check(w.side_for(A, bid) == "att" and w.side_for(L, bid) == "att" and w.side_for(S, bid) == "" and w.side_for(TM, bid) == "",
		"sides: Lions attack (any Lions clan); Stags, Ravens and the clanless can't join; nobody defends free land")
	check(w.seated(bid, A, ids[0], "Alice") and w.seated(bid, B, ids[1], "Bob") and not w.seated(bid, L, ids[4], "Lena") and w.attempts_left(A) == 4,
		"seated: Alice and Bob spend an attempt (Alice 4 left); Lena (another Lions clan) helps without one")
	check(w.seated(bid, A, ids[0], "Alice") and w.attempts_left(A) == 4, "back on her seat: not counted twice")
	w.started(bid)
	var res: Dictionary = w.battle_over(bid, {"won":true, "gate":true, "king":true, "present":[A]})
	check(int(res[A].pts) == 150 and int(res[A].crowns) == 3 and int(res[B].pts) == -100 and bool(res[B].quit) and int(res[A].bar) == 50
		and int(w.bars.mill[CA]) == 50 and not res.has(L), "won with 3 crowns: Alice +150, Bob (quit) -100: the Lions bar 50/500")
	check(w.battle_on("mill").is_empty(), "the battle is over")
	var hist: Array = s.hist.get("c:" + CA, [])
	check(str(hist.back().get("x", "")).contains("+50 (50/500)"), "the clan chat sums it up: %s" % str(hist.back().get("x", "")))
	# --- more battles until the Mill is taken
	var took := false
	for i in 3:
		s.handle(1, {"k":"war_go", "tid":"mill"})
		var b2 := str(last(1, "war_go").get("bid", ""))
		w.seated(b2, A, ids[0], "Alice")
		w.seated(b2, B, ids[1], "Bob")
		var r2: Dictionary = w.battle_over(b2, {"won":true, "gate":false, "king":true, "present":[A, B]})
		took = bool(r2[A].took)
		if took:
			break
	check(took and str(w.owners.mill.h) == "lions" and str(w.owners.mill.ct) == "LHRT" and (w.bars.mill as Dictionary).is_empty(),
		"enough wins: the Lions take the Mill (the bars start again)")
	check(str(w.captures[0].tid) == "mill" and str((s.hist.get("c:" + CA, []) as Array).back().get("x", "")).contains("took The Mill") or
		(s.hist.get("c:" + CA, []) as Array).any(func(l): return str(l.get("x", "")).contains("We took The Mill")), "the capture is logged and the clan told")
	check(w.attempts_left(A) == 1 and w.attempts_left(B) == 1, "attempts: Alice and Bob have 1 left each")
	clear()
	s.handle(1, {"k":"war_go", "tid":"mill"})
	check(str(last(1, "war_go").get("why", "")).contains("holds"), "their own land: refused")
	s.handle(1, {"k":"war_go", "tid":"tower"})
	var b3 := str(last(1, "war_go").get("bid", ""))
	w.seated(b3, A, ids[0], "Alice")
	w.battle_over(b3, {"won":false, "gate":false, "king":false, "present":[A]})
	check(w.attempts_left(A) == 0 and int(w.bars.get("tower", {}).get(CA, 0)) == 0, "a lost battle: -100 (never below 0); Alice is out of attempts")
	clear()
	s.handle(1, {"k":"war_go", "tid":"tower"})
	check(str(last(1, "war_go").get("why", "")).contains("No battles left"), "no attempts: can't start one")

	# ---------------- defending ----------------
	w.owners["tower"] = {"h":"stags", "c":CS, "ct":"STGP", "cn":"Stag Party", "at":T0}
	clear()
	s.handle(2, {"k":"war_go", "tid":"tower", "call":false})
	var b4 := str(last(2, "war_go").get("bid", ""))
	check(b4 != "" and got(1, "war_call").is_empty() and str(last(3, "war_alarm").get("bid", "")) == b4 and str(last(3, "war_alarm").get("ct", "")) == "LHRT",
		"Bob attacks the Stags' Tower without calling the clan: the Stags are alarmed")
	check(w.side_for(S, b4) == "def" and w.side_for(R, b4) == "" and w.need_for("tower") == 1000, "Stags defend; Ravens can't join; 1000 to take held land")
	clear()
	s.handle(3, {"k":"war_go", "tid":"tower"})
	check(str(last(3, "war_go").get("why", "")).contains("holds"), "the Stags can't attack their own Tower")
	s.handle(4, {"k":"war_go", "tid":"fen"})
	var bR := str(last(4, "war_go").get("bid", ""))
	var live := func() -> int: return w.battles.values().filter(func(b): return str(b.state) != "over").size()
	check(bR != "" and live.call() == 2, "Ravens attack the Fen meanwhile (one battle a territory, many at once)")
	w.battle_gone(bR)
	check(live.call() == 1 and not w.battles.has(bR) and w.attempts_left(R) == 4, "a battle nobody came to is dropped (the starter's attempt stays spent)")
	clear()
	s.handle(7, {"k":"war_go", "tid":"ford"})
	var bF := str(last(7, "war_go").get("bid", ""))
	check(bF != "" and live.call() == 2, "Cara (Lions) attacks the Ford: her clan has two battles on")

	# ---------------- the map's bars ----------------
	w.bars["quarry"] = {CA: 300}
	var lx: String = s.clans.clan_of(L)
	w.bars.quarry[lx] = 100
	clear()
	s.handle(1, {"k":"war_open"})
	var m2: Dictionary = last(1, "war")
	var qb: Array = m2.terr.quarry.bars
	check(qb.size() == 2 and str(qb[0].ct) == "LHRT" and int(qb[0].p) == 300 and str(m2.terr.mill.ct) == "LHRT" and str(m2.terr.mill.h) == "lions"
		and str(m2.terr.tower.b.bid) == b4 and str(m2.terr.tower.b.act) == "LHRT" and int(m2.att) == 0, "the map: bars, holders, the battle at the Tower, her attempts")
	check(int(m2.counts.lions) == 1 and int(m2.counts.stags) == 1, "territories per house")
	clear()
	w.owners["fen"] = {"h":"ravens", "c":s.clans.clan_of(R), "ct":"RVCL", "cn":"Raven Claw", "at":T0}
	w._mark()
	w.tick(1.0)
	check(not got(1, "war").is_empty(), "a change reaches the phones with the map open")
	s.handle(1, {"k":"war_close"})
	clear()
	w._mark()
	w.tick(1.0)
	check(got(1, "war").is_empty(), "closed: no more pushes")

	# ---------------- a new day, a new week ----------------
	s.now_override = T0 + 86400
	check(w.attempts_left(A) == 5, "a new day: 5 attempts again")
	clear()
	s.handle(1, {"k":"war_go", "tid":"quarry", "call":"yes"})
	check(str(last(1, "war_go").get("why", "")).contains("2 battles on already") and live.call() == 2,
		"a third battle for the clan: refused (and a malformed \"call\" still gets its answer)")
	w.bars["ford"] = {CA: 300}
	w.started(bF)
	w.battle_gone(bF)
	check(int(w.bars.ford[CA]) == 200 and not w.battles.has(bF), "every player left the Ford's battle while it ran: lost, Cara -100 (300 -> 200)")
	w.owners["quarry"] = {"h":"lions", "c":CA, "ct":"LHRT", "cn":"Lion Hearts", "at":T0}
	w.save_now()
	var again = World.new(dir, s)
	check(again.owners.size() == 4 and str(again.owners.mill.ct) == "LHRT" and int(again.bars.quarry[CA]) == 300 and str(again.week) == "2026-10-12",
		"world.json read back")
	s.now_override = T0 + 7 * 86400
	w._roll()
	check(str(w.last.get("won", "")) == "lions" and int(w.tally.get("lions", 0)) == 1 and int(w.last.counts.lions) == 2 and w.owners.is_empty()
		and w.bars.is_empty() and str(w.week) == "2026-10-19", "Monday: the Lions (2 territories) win the week; the map is free again")
	var rl: Dictionary = w.battle_over(b4, {"won":true, "gate":true, "king":true, "present":[B]})
	check(bool(rl[B].late) and int(rl[B].pts) == 0 and not bool(rl[B].took) and w.owners.is_empty() and w.bars.is_empty(),
		"Bob's battle for the Tower, still on when the week ended: it counts for nothing on the new map")
	w.save_now()
	# a damaged world.json: the odd entries are left out, and saving still works
	var wf := FileAccess.open(dir.path_join("world.json"), FileAccess.WRITE)
	wf.store_string(JSON.stringify({"v":1, "week":"2026-10-19", "owners":{"atlantis":{"h":"lions"}, "mill":{"h":"lions", "c":CA}, "lake":"x"},
		"bars":{"mill":{CA:"lots", "x":40}, "nowhere":{CA:5}}, "attempts":{A:"five", B:{"d":"2026-10-19", "n":2}}, "tally":{"lions":2, "goblins":9},
		"captures":[1, {"tid":"mill"}], "next_bid":"x"}))
	wf.close()
	var odd = World.new(dir, s)
	check(odd.owners.size() == 1 and odd.owners.has("mill") and (odd.bars.mill as Dictionary).size() == 1 and int(odd.bars.mill.x) == 40
		and not odd.bars.has("nowhere") and not odd.attempts.has(A) and odd.attempts.has(B) and odd.tally.size() == 1 and odd.captures.size() == 1,
		"a damaged world.json: only the entries that make sense are kept")
	odd.save_now()
	var back: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("world.json")))
	check(back is Dictionary and (back.owners as Dictionary).size() == 1, "... and it saves again")
	for f in ["world.json", "clans.json", "social.json"]:
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
	if fails.is_empty():
		print("WORLD_PASS")
	else:
		print("WORLD_FAIL %d: %s" % [fails.size(), str(fails)])
	quit(0 if fails.is_empty() else 1)
