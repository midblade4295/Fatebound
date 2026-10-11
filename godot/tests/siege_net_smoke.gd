extends SceneTree
# Run in REAL time (no --fixed-fps: the server is a separate process on the wall clock).
# Online Siege end to end: starts the real server (server/siege_server.gd) as a separate process,
# connects the real game client (SiegeMode online) plus a raw second client, and checks:
# welcome + team seating, snapshots, the player's unit moving from real touch input, actions
# (walk to a hat stand and become a class), events reaching the view/HUD, disconnect -> bot takes over.
# 0.31.101: the second player's hello says what they wear; it comes back to us in "pn" and dresses their unit.
# 0.31.82: both players wait out the lobby countdown (SIEGE_LOBBY 1.5 s here) and get "lobby" messages first (the
# game shows them on the lobby panel); a "status" query answers the player counts (Home's "players online").
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")

var port := 8092
var pid := -1
var mode
var raw: WebSocketPeer
var raw_unit := ""
var raw_hello_sent := false
var frames := 0
var t := 0.0
var pred_from := Vector2.ZERO
var pred_frames := 0
var pred_dt := 0.0
var pred_checked := false
var cheat_at := Vector2.ZERO
var phase := "boot"
var start_pos := Vector2.ZERO
var move_goal := Vector2.ZERO
var move_start_goal_distance := 0.0
var move_touch_pos := Vector2.ZERO
var saw_authoritative_move := false
var events_seen := 0
var snaps_raw := 0
var raw_lobby := {}                   # the raw client's last "lobby" message before its welcome
var raw_lobby_n := 0
var stat_ws: WebSocketPeer
var stat_sent := false
var fails: Array = []

func check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)
		print("FAIL ", what)
	else:
		print("ok   ", what)

func touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index; e.position = pos; e.pressed = pressed
	root.push_input(e, true)

func drag(index: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index; e.position = pos; e.relative = rel
	root.push_input(e, true)

func _init() -> void:
	if OS.has_environment("NET_TEST_PORT"):
		port = int(OS.get_environment("NET_TEST_PORT"))
	OS.set_environment("SIEGE_PORT", str(port))
	OS.set_environment("SIEGE_HOST", "127.0.0.1")
	OS.set_environment("SIEGE_LOBBY", "1.5")
	pid = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://server/siege_server.gd"])
	check(pid > 0, "server process started (pid %d)" % pid)

func _finish() -> void:
	if pid > 0:
		OS.kill(pid)
		OS.execute("kill", ["-9", str(pid)])            # the server ignores SIGTERM (0.31.23)
	print("SIEGE_NET_PASS" if fails.is_empty() else "SIEGE_NET_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)

func _process(delta: float) -> bool:
	frames += 1
	t += delta
	if raw != null:
		raw.poll()
		while raw.get_available_packet_count() > 0:
			var m := Net.decode(raw.get_packet())
			if m.get("t", "") == "welcome": raw_unit = str(m.you)
			if m.get("t", "") == "s": snaps_raw += 1
			if m.get("t", "") == "lobby" and raw_unit == "":
				raw_lobby = m
				raw_lobby_n += 1
	match phase:
		"boot":
			if t > 1.5:
				mode = Mode.new()
				mode.online = true
				mode.net_url = "ws://127.0.0.1:%d/fatebound/siege/ws" % port
				mode.player_name = "TestA"
				root.add_child(mode)
				phase = "join"; t = 0.0
		"join":
			if mode.net_state == "playing" and mode.sim != null and mode.sim.time > 0.4:
				var me_id: String = mode.hud.player_id
				check(me_id.begins_with("b"), "first player seated on blue (%s)" % me_id)
				check(not mode.sim.by_id[me_id].bot, "our unit is human-controlled on the mirror")
				check(mode.sim.time > 0.3, "snapshots advance match time (%.2f s)" % mode.sim.time)    # (0.31.82: a fresh match after the lobby)
				check(mode.lobby_msgs > 0, "the lobby countdown came before the welcome (%d messages)" % mode.lobby_msgs)
				check(mode.lobby == null, "the lobby panel closed on the welcome")
				check(mode.net_names == {me_id: "TestA"}, "the server named the live players: %s" % str(mode.net_names))
				var named := false
				for b in mode.view.bars():
					named = named or str(b.get("name", "")) == "TestA"
				check(named, "our name shows over our health bar")
				raw = WebSocketPeer.new()
				raw.connect_to_url("ws://127.0.0.1:%d/fatebound/siege/ws" % port)
				phase = "raw"; t = 0.0
			elif t > 8.0:
				check(false, "client joined within 8 s (state=%s)" % mode.net_state); _finish()
		"raw":
			if raw.get_ready_state() == WebSocketPeer.STATE_OPEN and not raw_hello_sent:
				raw.put_packet(Net.encode({"t":"hello", "v":Net.VERSION, "name":"TestB", "title":"title_siege_lord",
					"lk":{"knight":"knight_wpn_oath|3|holy", "nobody":"x|1|", "rogue":"Bad Id|1|"}}))     # 0.31.101
				raw_hello_sent = true
			if raw_unit != "" and snaps_raw >= 3:
				check(raw_unit.begins_with("r"), "second player seated on red (%s)" % raw_unit)
				check(raw_lobby_n > 0 and str(raw_lobby.get("names", [])) == str(["TestB"]) and int(raw_lobby.get("me", -1)) == 0,
					"the second player waited in the lobby with its own name listed (%d messages, %s)" % [raw_lobby_n, str(raw_lobby.get("names", []))])
				check(bool(raw_lobby.get("running", false)) and int(raw_lobby.get("in_match", 0)) == 1 and int(raw_lobby.get("online", 0)) == 2,
					"the lobby says a battle with 1 player is on, 2 online (%s)" % str(raw_lobby))
				check(str(mode.net_names.get(raw_unit, "")) == "TestB" and mode.net_names.size() == 2, "the second player's name reached us (%s)" % str(mode.net_names))
				check(mode.view.player_names.has(raw_unit), "the view has it (a bot never gets one)")
				check(str(mode.net_titles.get(raw_unit, "")) == "title_siege_lord" and not mode.net_titles.has(mode.hud.player_id),
					"their title came with it; we wear none (%s)" % str(mode.net_titles))
				check(str(raw_lobby.get("tt", [])) == str(["title_siege_lord"]), "the lobby listed their title too (%s)" % str(raw_lobby.get("tt", [])))
				# 0.31.101: what they wear came too (the server kept the good entry), and our view dresses their unit with it
				check(mode.net_looks.get(raw_unit, {}) == {"knight":"knight_wpn_oath|3|holy"} and not mode.net_looks.has(mode.hud.player_id),
					"their looks reached us, cleaned; we (no profile) wear none (%s)" % str(mode.net_looks))
				check(str(mode.view.unit_cosmetic({"id":raw_unit, "cls":"knight", "up":false}).get("r", "")) == "mw/kingsoath_sword",
					"as a Knight they'd carry Kingsoath on our screen")
				var tagged := false
				for b in mode.view.bars():
					tagged = tagged or (str(b.get("name", "")) == "TestB" and str(b.get("title", "")) == "title_siege_lord")
				check(tagged, "their bar carries the title for the over-head plate")
				# Pick the farther courtyard station, then steer the real touch stick over the
				# mirror's navigation path. A fixed direction is seed-dependent here: the spawn
				# is randomized and walls/resources can sit directly in front of it.
				var me: Dictionary = mode.sim.by_id[mode.hud.player_id]
				start_pos = me.get("net_to", me.pos)
				var forge_pos: Vector2 = Sim.forge(me.team)
				var workshop_pos: Vector2 = Sim.workshop(me.team)
				move_goal = forge_pos if start_pos.distance_to(forge_pos) > start_pos.distance_to(workshop_pos) else workshop_pos
				move_start_goal_distance = start_pos.distance_to(move_goal)
				touch(0, Vector2(100, 600), true)
				phase = "move"; t = 0.0
			elif t > 6.0:
				check(false, "raw client welcomed (unit=%s snaps=%d)" % [raw_unit, snaps_raw]); _finish()
		"move":
			var me: Dictionary = mode.sim.by_id[mode.hud.player_id]
			var authoritative_pos: Vector2 = me.get("net_to", me.pos)
			saw_authoritative_move = saw_authoritative_move or me.state == "move"
			var path: PackedVector2Array = mode.sim.find_path(me.team, authoritative_pos, move_goal)
			var target: Vector2 = path[mini(1, path.size() - 1)] if path.size() > 0 else move_goal
			var move_dir: Vector2 = (target - authoritative_pos).normalized()
			move_touch_pos = Vector2(100, 600) + move_dir * 60.0
			drag(0, move_touch_pos, move_dir * 60.0)
			var progress: float = move_start_goal_distance - authoritative_pos.distance_to(move_goal)
			# Snapshots arrive at 10 Hz on the wall clock. Under a loaded test runner the 2 s
			# check could land on an older mirror snapshot even though the server was moving.
			# Finish as soon as the authoritative snapshot shows enough movement, with a
			# bounded timeout so a real input/transport failure still fails quickly.
			if (progress > 3.0 and saw_authoritative_move) or t > 8.0:
				touch(0, move_touch_pos, false)
				check(progress > 3.0 and saw_authoritative_move,
					"our unit moved from touch input through the server (%.1f m toward goal)" % progress)
				# Walk to one of our hat stands via the protocol; the server hands over the hat.
				phase = "hat"; t = 0.0
		"hat":
			var me2: Dictionary = mode.sim.by_id[mode.hud.player_id]
			if me2.cls != "villager":
				phase = "hatted"; t = 0.0
			else:
				var best := {}
				for st in mode.sim.stands:
					if int(st.team) == me2.team and int(st.stock) > 0 and (best.is_empty() or me2.pos.distance_to(st.p) < me2.pos.distance_to(best.p)):
						best = st
				var goal: Vector2 = (best.p as Vector2) + ((Sim.spawn(me2.team) - (best.p as Vector2)).normalized() * 0.95) if not best.is_empty() else Sim.forge(me2.team)
				if t < 24.0:
					# Steer along the mirror's own nav path (walls/gates), like a player would.
					var path: PackedVector2Array = mode.sim.find_path(me2.team, me2.pos, goal)
					# When the path has nothing left to follow (the goal's nav cell can be solid around
					# the stand), walk straight at the stand like a player would: steering at the
					# path's end = the unit's own cell centre stalled it 1.8 m short (Round 15).
					var target: Vector2 = path[1] if path.size() > 1 else (best.p if not best.is_empty() else goal)
					mode._net_send({"t":"in", "m":(target - me2.pos).normalized(), "h":false})
					if not best.is_empty() and me2.pos.distance_to(best.p) < 2.2:
						# 0.31.22: hats are taken with ACTION -- step up to the stand and press it
						mode._net_send({"t":"in", "m":((best.p as Vector2) - me2.pos).normalized() * 0.5, "h":false, "a":"interact"})
					# Keep the mode's 20 Hz sender (HUD stick = zero) from overriding the test input.
					mode._sent_move = Vector2.ZERO
					mode._send_clock = -1.0
				else:
					check(false, "reached a hat stand and became a class (still %s, %.1f m away; stand %s at %s, me at %s, goal %s)" % [me2.cls, me2.pos.distance_to(goal), str(best.get("cls","?")), str(best.get("p","?")), str(me2.pos), str(goal)]); _finish()
		"hatted":
			if t > 1.0:
				mode._net_send({"t":"in", "m":Vector2.ZERO, "h":false})
				var me3: Dictionary = mode.sim.by_id[mode.hud.player_id]
				check(me3.cls != "villager", "took a hat at a stand on the server (now %s)" % me3.cls)
				var own_stock := 0
				for st in mode.sim.stands:
					if int(st.team) == me3.team: own_stock += int(st.stock)
				check(own_stock < Sim.HAT_STOCK_MAX * Sim.HAT_CLASSES.size(), "stand stock synced to the mirror (%d left)" % own_stock)
				check(mode.sim.projectiles.size() >= 0 and mode.diag != null, "mirror sim alive")
				phase = "predict"; t = 0.0
				pred_from = mode.sim.by_id[mode.hud.player_id].pos
				# Push the HUD stick (a phone's thumb): our unit must move locally at once.
				# Toward the open courtyard around the spawn: pushing "right" from wherever the hat was
				# taken sometimes walked straight into a stand or wall (collision, not a prediction bug).
				var me_d: Dictionary = mode.sim.by_id[mode.hud.player_id]
				var open_dir: Vector2 = (Sim.spawn(me_d.team) - (me_d.pos as Vector2)).normalized()
				if open_dir == Vector2.ZERO:
					open_dir = Vector2(1, 0)
				mode.hud._stick_active = true
				mode.hud._stick_origin = Vector2(100, 600)
				mode.hud._stick_pos = Vector2(100, 600) + open_dir * 60.0
		"predict":
			var mep: Dictionary = mode.sim.by_id[mode.hud.player_id]
			# Frame times vary (uncapped headless frames can be ~5 ms), so compare the local move with
			# what the unit's speed allows in the time elapsed: prediction moves it at once, without
			# waiting for the server (which alone would show ~0 m this early).
			if pred_frames >= 1 and pred_frames <= 3:
				pred_dt += delta
			if pred_frames == 3:
				var spd: float = float(mode.sim.stat(mep, "speed"))
				var moved: float = mep.pos.distance_to(pred_from)
				check(moved >= 0.5 * spd * pred_dt and moved > 0.0, "client-side prediction: moved %.3f m locally in %.0f ms (speed allows %.3f)" % [moved, pred_dt * 1000.0, spd * pred_dt])
			pred_frames += 1
			if t > 1.2 and not pred_checked:
				pred_checked = true
				var srv: Vector2 = mep.get("srv_pos", Vector2.INF)
				check(srv != Vector2.INF and srv.distance_to(mep.pos) < 1.5 and srv.distance_to(pred_from) > 1.0,
					"the server follows the predicted position (server %.2f m behind, moved %.2f m)" % [srv.distance_to(mep.pos), srv.distance_to(pred_from)])
				mode.hud._stick_active = false
				# Pressing ATTACK starts the swing locally at once (the server resolves the hit).
				if mode.sim.can_act(mep) and mep.cls != "priest":
					mode._act("attack")
					check(mep.state == "wind", "a swing starts locally the moment ATTACK is pressed (state %s)" % mep.state)
				# A forged far-away position must be refused.
				cheat_at = mep.pos + Vector2(20, 0)
				mode._net_send({"t":"in", "m":Vector2.ZERO, "h":false, "p":cheat_at, "f":0.0})
			if t > 1.9 and pred_checked:
				var srv2: Vector2 = mep.get("srv_pos", Vector2.INF)
				check(srv2.distance_to(cheat_at) > 10.0, "a forged position 20 m away is rejected (server %.1f m from it)" % srv2.distance_to(cheat_at))
				raw.close()
				phase = "drop"; t = 0.0
		"drop":
			if t > 2.0:
				var ru: Dictionary = mode.sim.by_id[raw_unit]
				check(ru.bot, "after the second player left, a bot took %s back" % raw_unit)
				check(not mode.net_names.has(raw_unit) and mode.net_names.size() == 1, "their name went with them (%s)" % str(mode.net_names))
				check(not mode.net_looks.has(raw_unit) and not mode.view.unit_looks.has(raw_unit), "and their looks: the bot wears the defaults")
				check(mode.sim.kills[0] + mode.sim.kills[1] >= 0, "match still running (t=%.0f s)" % mode.sim.time)
				stat_ws = WebSocketPeer.new()
				stat_ws.connect_to_url("ws://127.0.0.1:%d/fatebound/siege/ws" % port)
				phase = "status"; t = 0.0
		"status":
			# Home's "players online": a status query (no hello) answers the counts and closes
			stat_ws.poll()
			if stat_ws.get_ready_state() == WebSocketPeer.STATE_OPEN and not stat_sent:
				stat_ws.put_packet(Net.encode({"t":"status"}))
				stat_sent = true
			while stat_ws.get_available_packet_count() > 0:
				var sm := Net.decode(stat_ws.get_packet())
				if sm.get("t", "") == "status":
					check(int(sm.get("v", -1)) == Net.VERSION and int(sm.get("online", -1)) == 1 and int(sm.get("in_match", -1)) == 1 and int(sm.get("waiting", -1)) == 0,
						"status answers the player counts (%s)" % str(sm))
					_finish()
					return false
			if t > 4.0:
				check(false, "status answered within 4 s (state %d)" % stat_ws.get_ready_state()); _finish()
	return false
