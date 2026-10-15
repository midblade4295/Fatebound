extends SceneTree
# 0.31.135 (Crown War step 2): a battle on the war map, end to end against the real server (its own process, port 8120,
# a 6-second match that the attackers win 1-0, SIEGE_TEST_SCORE). Before it starts: the Lions clan [LION] (Alice, Bob)
# holds the Mill, the Stags clan [STAG] (Sam) holds the Old Tower (clans.json and world.json written for it). Alice
# opens the map and attacks the Tower, calling her clan: Bob is called, Sam (a holder) is alarmed. Bob and Alice join
# on team 1 (red), Sam defends on team 0 (blue); Rae (no clan) is refused. The battle starts after its countdown, ends
# 1-0: Alice and Bob each earn 100 (the rescue and the win), the Lions' bar on the Tower is
# 200/1000; Sam hears the Tower held. PLAY AGAIN after it: "war_over". The map shows the bar.
# The server has 1 room (SIEGE_MAX_ROOMS; 0.31.151: battles may take every room): Alice's battle takes it, so Sam's
# attack on the Mill meanwhile is "busy". A second socket of Bob's account is turned away (war_twice). Bob's phone never asks for the next match, yet
# he's let go after the results (SIEGE_RESULTS_KEEP 3 s); joining the battle after it: war_over. Once everyone's gone
# the room closes and Sam's attack goes through.
#   godot --headless --path godot -s res://tests/war_battle_test.gd
const ClientSocial = preload("res://scripts/meta/social.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const EcoAccounts = preload("res://server/eco_accounts.gd")
const Social = preload("res://server/social.gd")
const Leaderboard = preload("res://server/leaderboard.gd")
const Net = preload("res://scripts/siege/siege_net.gd")

var port := 8120
var server_pid := -1
var fails: Array = []
var phase := "boot"
var t := 0.0
var t_phase := 0.0
var raw := {}
var accts := {}
var socs := {}
var bid := ""
var retry_at := -10.0

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	var sd := OS.get_user_data_dir().path_join("warbattle-srv-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(sd)
	var eco := EcoAccounts.new(sd)
	for n in ["Alice", "Bob", "Sam", "Rae"]:
		var e: Dictionary = eco.create({})
		e.p.d.name = n
		e.p.d.level = 10
		e.p.d.tutorial_done = true
		e.p.save()
		accts[n] = [str(e.id), str(e.key_plain)]
	# the clans and the map as they stand when the server starts
	var now := int(Time.get_unix_time_from_system())
	var pa := Social.pid_of(accts.Alice[0])
	var pb := Social.pid_of(accts.Bob[0])
	var ps := Social.pid_of(accts.Sam[0])
	var clans := {"clion": {"id":"clion", "name":"Lion Hearts", "tag":"LION", "house":"lions", "join":"open", "min_lv":1, "leader":pa,
		"officers":[], "members":{pa: now, pb: now}, "req":{}, "created":now},
		"cstag": {"id":"cstag", "name":"Stag Party", "tag":"STAG", "house":"stags", "join":"open", "min_lv":1, "leader":ps,
		"officers":[], "members":{ps: now}, "req":{}, "created":now}}
	_write(sd.path_join("clans.json"), {"v":1, "clans":clans, "inv":{}, "cool":{}})
	_write(sd.path_join("world.json"), {"v":1, "week":Leaderboard.week_of(now), "owners":{
		"mill": {"h":"lions", "c":"clion", "ct":"LION", "cn":"Lion Hearts", "at":now},
		"tower": {"h":"stags", "c":"cstag", "ct":"STAG", "cn":"Stag Party", "at":now}}, "bars":{}, "attempts":{}, "tally":{}, "last":{}})
	OS.set_environment("SIEGE_PORT", str(port))
	OS.set_environment("SIEGE_HOST", "127.0.0.1")
	OS.set_environment("SIEGE_LOBBY", "1.0")
	OS.set_environment("SIEGE_WAR_LOBBY", "4.0")
	OS.set_environment("SIEGE_TEST_MATCH_S", "6")
	OS.set_environment("SIEGE_TEST_SCORE", "0:1")
	OS.set_environment("SIEGE_IDLE_STOP", "2")
	OS.set_environment("SIEGE_MAX_ROOMS", "1")
	OS.set_environment("SIEGE_RESULTS_KEEP", "3")
	OS.set_environment("STATE_DIRECTORY", sd)
	OS.set_environment("SIEGE_MIN_BUILD", "off")
	server_pid = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://server/siege_server.gd"])
	check(server_pid > 0, "server process started")

func _write(path: String, d: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()

func _ws(name: String, first: Dictionary) -> void:
	var ws := WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 21
	ws.connect_to_url("ws://127.0.0.1:%d" % port)
	raw[name] = {"ws":ws, "sent":false, "first":first, "msgs":[]}

func _hello(n: String, as_name := "", ask_next := true) -> void:
	_ws("m_" + (as_name if as_name != "" else n), {"t":"hello", "v":Net.VERSION, "name":n, "build":"0.31.135-fatebound", "pred":false,
		"ask_next":ask_next, "acct":accts[n][0], "key":accts[n][1], "war":bid})

func _poll_raw() -> void:
	for n in raw:
		var r: Dictionary = raw[n]
		var ws: WebSocketPeer = r.ws
		ws.poll()
		var now_s := Time.get_ticks_msec() / 1000.0
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED and not bool(r.sent) and now_s - float(r.get("dialed", 0.0)) > 0.5:
			# 0.31.145: the server (its own process) may not be listening yet on a slow machine -- dial again
			r.dialed = now_s
			ws.connect_to_url("ws://127.0.0.1:%d" % port)
			continue
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN and not bool(r.sent):
			ws.put_packet(Net.encode(r.first))
			r.sent = true
		while ws.get_available_packet_count() > 0:
			(r.msgs as Array).append(Net.decode(ws.get_packet()))

func _got(name: String, kind: String) -> Array:
	return (raw.get(name, {}).get("msgs", []) as Array).filter(func(m): return str(m.get("t", "")) == kind)

func _go(next: String) -> void:
	phase = next
	t_phase = 0.0

func _process(delta: float) -> bool:
	t += delta
	t_phase += delta
	_poll_raw()
	if t > 90.0:
		check(false, "timed out in phase %s" % phase)
		return _finish()
	match phase:
		"boot":
			if t_phase > 1.5:
				for n in ["Alice", "Bob", "Sam"]:
					var p = Profile.new("user://warbattle-%s-%d.json" % [n, Time.get_ticks_usec()], "user://none.json")
					p.load_or_create()
					p.d.account = {"id":accts[n][0], "key":accts[n][1], "seq":0}
					var so = ClientSocial.new()
					so.url = "ws://127.0.0.1:%d" % port
					so.setup(p)
					root.add_child(so)
					_listen(so)
					so.set_active(true)
					socs[n] = so
				_go("online")
		"online":
			# (the clan state follows "online" a moment later on a slow machine: wait for the tags too)
			if socs.Alice.online() and socs.Bob.online() and socs.Sam.online() and t_phase > 0.5 \
					and ((socs.Alice.my_tag() != "" and socs.Sam.my_tag() != "") or t_phase > 8.0):
				check(socs.Alice.my_tag() == "LION" and socs.Sam.my_tag() == "STAG", "the clans are there (LION, STAG)")
				socs.Alice.war_open()
				_go("map")
		"map":
			var last_war := _last_so(socs.Alice, "war")
			if not last_war.is_empty():
				check(str(last_war.terr.mill.h) == "lions" and str(last_war.terr.tower.ct) == "STAG" and str(last_war.terr.tower.why) == "" and int(last_war.att) == 5,
					"the map: the Mill is the Lions', the Tower the Stags' -- the Lions may attack it")
				socs.Alice.war_go("tower", true)
				_go("go")
		"go":
			var g := _last_so(socs.Alice, "war_go")
			if not g.is_empty():
				check(bool(g.get("ok", false)), "Alice attacks the Old Tower: %s" % str(g))
				bid = str(g.get("bid", ""))
				_hello("Alice")
				socs.Sam.war_go("mill", false)
				_go("busy")
		"busy":
			var sg := _last_so(socs.Sam, "war_go")
			if not sg.is_empty():
				check(not bool(sg.get("ok", true)) and str(sg.get("why", "")).contains("busy"), "1 room, Alice's battle in it: Sam's attack on the Mill is busy")
				socs.Sam.set_meta("seen_war_go", {})
				_go("calls")
		"calls":
			var call := _last_so(socs.Bob, "war_call")
			var alarm := _last_so(socs.Sam, "war_alarm")
			if not call.is_empty() and not alarm.is_empty():
				check(str(call.bid) == bid and str(call.by) == "Alice" and str(alarm.bid) == bid and str(alarm.ct) == "LION", "Bob is called to it, Sam is alarmed")
				_hello("Bob", "", false)
				_hello("Sam")
				_ws("m_Rae", {"t":"hello", "v":Net.VERSION, "name":"Rae", "build":"0.31.135-fatebound", "pred":false,
					"acct":accts.Rae[0], "key":accts.Rae[1], "war":bid})
				_go("seated")
		"seated":
			var wa := _got("m_Alice", "welcome")
			var wb := _got("m_Bob", "welcome")
			var ws := _got("m_Sam", "welcome")
			if not wa.is_empty() and not wb.is_empty() and not ws.is_empty():
				check(str(wa[0].you).begins_with("r") and str(wb[0].you).begins_with("r") and str(ws[0].you).begins_with("b"),
					"attackers on red (Alice %s, Bob %s), the defender on blue (Sam %s)" % [str(wa[0].you), str(wb[0].you), str(ws[0].you)])
				var bye := _got("m_Rae", "bye")
				check(not bye.is_empty() and str(bye[0].why) == "war_side", "Rae (no clan) is refused")
				_hello("Bob", "Bob2")
				var lob := _got("m_Alice", "lobby")
				check(not lob.is_empty() and float(lob[0].get("wait", 0)) >= 3.9, "the battle's countdown is the war lobby's (%s s)" % str(lob[0].get("wait", "?") if not lob.is_empty() else "?"))
				_go("counts")
		"counts":
			# 0.31.149: the open map hears who's in the battle (the hot zones): Alice and Bob attacking, Sam defending
			var lw := _last_so(socs.Alice, "war")
			var tb: Dictionary = lw.get("terr", {}).get("tower", {}).get("b", {})
			if int(tb.get("na", 0)) == 2 and int(tb.get("nd", 0)) == 1:
				check(true, "the map says who's in the battle: 2 attacking, 1 defending")
				_go("result")
			elif t_phase > 6.0 or not _got("m_Alice", "war").is_empty():
				check(false, "the map says who's in the battle (%s)" % str(tb))
				_go("result")
		"result":
			var ra := _got("m_Alice", "war")
			var rs := _got("m_Sam", "war")
			if not ra.is_empty() and not rs.is_empty():
				var a: Dictionary = ra[0]
				check(int(a.pts) == 100 and int(a.crowns) >= 2 and bool(a.won) and bool(a.king) and int(a.bar) >= 200 and int(a.need) == 1000 and not bool(a.took),
					"Alice: won with the rescue: +%d, %d crowns, the bar %d/%d" % [int(a.pts), int(a.crowns), int(a.bar), int(a.need)])
				var rb := _got("m_Bob", "war")
				check(not rb.is_empty() and int(rb[0].pts) == int(a.pts), "Bob's battle counts too")
				var b2 := _got("m_Bob2", "bye")
				check(not b2.is_empty() and str(b2[0].why) == "war_twice", "a second socket of Bob's account: refused (war_twice)")
				check(bool(rs[0].get("def", false)) and bool(rs[0].get("held", false)), "Sam: the Tower held")
				(raw.m_Alice.ws as WebSocketPeer).put_packet(Net.encode({"t":"again"}))
				_go("again")
		"again":
			var bye := _got("m_Alice", "bye")
			var mw := _last_so(socs.Alice, "war")
			if not bye.is_empty() and not mw.is_empty() and not (mw.terr.tower.get("bars", []) as Array).is_empty():
				check(str(bye[0].why) == "war_over", "PLAY AGAIN after a battle: war_over")
				var bars: Array = mw.terr.tower.get("bars", [])
				check(not bars.is_empty() and str(bars[0].ct) == "LION" and int(bars[0].p) >= 200,
					"the map: the Lions' bar on the Tower")
				check(not mw.terr.tower.has("b") or str(mw.terr.tower.b.state) == "over", "no live battle at the Tower now")
				var lines: Array = socs.Bob.lines.get("clan", [])
				check(lines.any(func(l): return str(l.get("x", "")).contains("The battle for Old Tower")), "the clan chat sums the battle up")
				_hello("Sam", "Sam2")
				_go("letgo")
		"letgo":
			var bb := _got("m_Bob", "bye")
			var s2 := _got("m_Sam2", "bye")
			if not bb.is_empty() and not s2.is_empty():
				check(str(bb[0].why) == "done", "Bob (never asks for the next match) is let go after the battle's results")
				check(str(s2[0].why) == "war_over", "joining the battle after it: war_over")
				_go("closed")
		"closed":
			# (the room closes once its finished match is let go -- SIEGE_IDLE_STOP -- so "busy" until then: ask again)
			var sg2 := _last_so(socs.Sam, "war_go")
			if not sg2.is_empty() and bool(sg2.get("ok", false)):
				check(true, "everyone gone: the room closed, and Sam's attack on the Mill goes through")
				_go("end")
			elif t_phase > 10.0:
				check(false, "everyone gone: the room closed, and Sam's attack on the Mill goes through (%s)" % str(sg2))
				_go("end")
			elif t_phase - retry_at > 1.0:
				retry_at = t_phase
				socs.Sam.set_meta("seen_war_go", {})
				socs.Sam.war_go("mill", false)
		"end":
			if t_phase > 0.3:
				return _finish()
	return false

func _last_so(so, k: String) -> Dictionary:
	if k == "war":
		return so.war
	return so.get_meta("seen_" + k, {})

func _listen(so) -> void:
	so.war_went.connect(func(m): so.set_meta("seen_war_go", m))
	so.war_called.connect(func(m): so.set_meta("seen_war_call", m))
	so.war_alarmed.connect(func(m): so.set_meta("seen_war_alarm", m))

func _finish() -> bool:
	if server_pid > 0:
		OS.kill(server_pid)
	print("WAR_BATTLE_PASS" if fails.is_empty() else "WAR_BATTLE_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
	return true
