extends Control
# Offline Siege match: you plus bots. Owns the simulation, steps it at a fixed rate, and feeds the
# 3D view and HUD. Emits `exited` when the player leaves.
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Land = preload("res://scripts/siege/siege_land.gd")
const Keep = preload("res://scripts/siege/keep.gd")
const View = preload("res://scripts/siege/siege_view.gd")
const Hud = preload("res://scripts/siege/siege_hud.gd")
const Diag = preload("res://scripts/siege/siege_diag.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const VisualTheme = preload("res://scripts/ui/visual_theme.gd")
const Loading = preload("res://scripts/siege/loading_screen.gd")   # 0.31.208: the lobby and the loading card, one screen
const Moba = preload("res://scripts/siege/moba.gd")

signal exited
# 0.31.73: the server refused our protocol. verdict "update" (server newer: this build is too old -> the app shows
# the blocking Update screen) or "server_old" (server older: "Servers are updating"). See Net.version_verdict.
signal version_mismatch(server_v: int, verdict: String)

var team_size := 16
var moba_hero := ""            # 0.31.155 5V5 (the test): your hero; a 5v5 against bots, offline (scripts/siege/moba.gd)
var match_seed := -1           # (benchmarks: a fixed match; -1 the clock's)
var analytics = null          # 0.31.118: usage statistics (scripts/meta/analytics.gd): VS BOTS matches and the tutorial
var _an_match := ""           #   (the server counts online matches itself)
var _an_class0 := ""
const Analytics = preload("res://scripts/meta/analytics.gd")
const TUTORIAL_GOLD := 250
# 3D resolution as a fraction of the PHYSICAL screen (window pixels, not logical UI units).
# 0.31.163 (Kevin: "lock it to 30fps and 50% resolution. Remove settings so players don't see"): locked at 50 % -- on his
# S21 Ultra the graphics chip took ~22 ms a frame there against ~36 at 75 % and ~46 at 100 %, and only 50 % held 30 fps.
# No RESOLUTION button any more, no heat guard stepping it (set_render_scale stays for the benches).
const RENDER_SCALE := 0.5
var render_scale := RENDER_SCALE
const FPS_CAP := 30         # hard-locked, no fps options (Round 32; 60 for one test build, 0.31.162) -- the sim ticks at 30 Hz
var _prev_max_fps := 0
var _prev_physics_tps := 60
var fps_cap := FPS_CAP
var low_fx := false
var hq_gfx := true          # High-quality graphics (Settings): shadows, glow, smoother edges
var replay_hero := ""       # 0.31.164: PLAY AGAIN after a 5v5 -- siege_app starts the next one (with its own ticket)
var tutorial := false       # 0.31.181: the 5v5 tutorial (scripts/siege/tutorial.gd): a quiet match against bots, the
var tutorial_ui = null      #   Herald over it (the app's start_tutorial); no ticket, no match rewards -- its own gold once
var _tut_done := false
var _tut_t0 := 0
const Tutorial = preload("res://scripts/siege/tutorial.gd")
var audio: Node = null
var profile = null       # scripts/meta/profile.gd — rewards, challenges and cosmetics
var rewards: Dictionary = {}
var match_result: Dictionary = {}
# 0.31.87 (titles): what the match counts toward them, gathered here so offline and online count the same way
var _cls_time := {}      # class -> seconds played as it (alive; the upgrade counts as its class)
var _kills_cls := {}     # class -> knockouts made as it
var _kills_seen := 0
var _best_multi := 0     # most knockouts in one burst ("multikill" events)
# 0.31.97 (class quests): the same, per class as worn -- a Crusader apart from a Knight (Eco.cosmetic_class)
const Q_UNIT := {"kills":"kills", "gate_dmg":"gate_dmg", "healed":"healed",
	"towers":"towers", "camps":"camps", "lh":"lh", "epics":"epics"}       # (0.31.164: the 5v5's, moba.gd counts them on the hero)
var _q := {}             # worn class -> {"t": seconds, "kills", "gate_dmg", "healed", "best_multi", "towers", "camps", "lh", "epics"}
var _q_seen := {}        # my unit's running totals already credited
var _q_cls := ""         # the class I wear right now ("" = none)

# Online play (set before adding to the tree). The server runs the match; this client mirrors it.
var online := false
# SIEGE_URL overrides the server for desktop testing (e.g. ws://127.0.0.1:8082/fatebound/siege/ws).
var net_url := OS.get_environment("SIEGE_URL") if OS.has_environment("SIEGE_URL") else Net.DEFAULT_URL
var player_name := "Player"
var ws: WebSocketPeer = null
var net_state := ""                  # "connecting", "waiting", "playing", "closed"
var net_match := -1
var net_verdict := ""               # 0.31.73: "update" / "server_old" after a version refusal
var net_server_version := -1        # the server's protocol from that refusal
var _net_bye: Dictionary = {}
var _net_closing_since := -1.0
var _me_bot := false                # 0.31.119: the server says a bot plays my unit (I was idle): no prediction
# 0.31.120 (Kevin: rejoin after a dropped connection): the server's token for my seat ("rj" in the welcome). When the
# connection drops mid-match the game keeps the match on screen and reconnects quietly every REJOIN_EVERY s for up to
# REJOIN_FOR s with a hello carrying the token; the server puts me straight back on my unit (welcome "rejoin").
const REJOIN_FOR := 55.0
const REJOIN_EVERY := 2.0
var rejoin_for := REJOIN_FOR        # (tests shorten it)
var _rj := ""
var _rejoin_until := -1.0
var _rejoin_at := 0.0
var _rejoin_sent := false
var rejoins := 0                    # (tests, diag)
var again_sent := 0                 # 0.31.122: PLAY AGAIN presses sent to the server (tests)
var party_join := ""                # 0.31.120: a friend's public id: their match is the one to join (Friends > JOIN)
var exit_note := ""                 # 0.31.119: why the match ended for me, for Home to say (removed for being idle)
const MSG_UPDATE := "A new version of Fatebound is available. Update to keep playing."
const MSG_SERVER_OLD := "Servers are updating, try again in a few minutes"
var _net_started := 0.0
var _snap_t := 0.0
var _net_rt := -1.0                 # 0.31.23: the render clock (server seconds) remote units are drawn at
var _net_latest := 0.0              # the newest snapshot's server time
var _net_delay := Net.INTERP_DELAY  # 0.31.24: the draw delay in use (grows with jitter, up to 250 ms)
var _net_jitter := 0.0              # smoothed |arrival gap - snapshot interval|
var _net_rx_last := 0.0
var _pred_fx := {}                  # ability effects shown ahead of the server, by kind: time
var _snap_dt := 1.0 / Net.SNAP_HZ
var _send_clock := 0.0
var _sent_move := Vector2(INF, INF)
var _sent_hold := false
var _sent_bhold := false
var lobby: Control = null           # 0.31.82: the join countdown, from PLAY until the welcome
var lobby_msgs := 0                 # "lobby" messages received (tests)
var net_names := {}                 # unit id -> name of each live player in the match (0.31.86, the server's "pn")
var net_titles := {}                # unit id -> their title id (0.31.87, the "pn" message's "tt")
var net_looks := {}                 # unit id -> their looks ({"_sk": the outfits}): what they wear (0.31.101, "pn" "lk")
var net_tags := {}                  # unit id -> clan tag (0.31.134, "pn" "ct")
var clan_tag := ""                  # 0.31.134: the player's own clan tag (set by the app; shown on your plate)
var clan_crest := ""                # 0.31.196: ... and crest
var net_crests := {}                # 0.31.196: unit id -> clan crest code ("pn" "cc")

var sim
var view
var hud
var viewport: SubViewport
var diag
var _accum := 0.0
var _result_shown := false

static var ready_times := {}      # ms per start-up step of the last match (diag / tools)

func _ready() -> void:
	ready_times = {}
	var t_ready := Time.get_ticks_msec()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	diag = Diag.new()
	diag.mode = self
	add_child(diag)
	ready_times["diag"] = Time.get_ticks_msec() - t_ready
	# Cap Siege's frame rate: uncapped on a 120 Hz phone it ran flat out and thermal-throttled
	# within ~70 s (field log, S21 Ultra). Restored when leaving.
	_prev_max_fps = Engine.max_fps
	set_fps_cap(FPS_CAP)
	# 0.31.160 (Kevin's phone log, 5v5 at 14-20 fps): the physics -- only the ragdolls and the loose weapons -- at the
	# frame cap's rate: steps beyond one a drawn frame buy nothing to see (at the 30 cap and 15 fps it had been four at
	# the engine's 60; tests/moba_bench.gd: ~1.3 ms a step here with a 5v5's eight ragdolls and twenty loose weapons).
	# 0.31.162: the cap is 60, so 60 Hz. Restored on leaving.
	_prev_physics_tps = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = FPS_CAP
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	# 2x (Round 35): 4x with High-quality graphics was the largest single cost in a big fight (tests/battle_bench.gd:
	# 4x -> 2x more than halved the frame).
	viewport.msaa_3d = Viewport.MSAA_2X
	# Same 3D viewport settings as the (removed) dice battle, which ran full matches on the
	# phone that crashes in Siege: default mesh LOD threshold, update when visible.
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport.handle_input_locally = false
	viewport.gui_disable_input = true
	viewport.size = Vector2i(64, 64)
	add_child(viewport)
	var tex := TextureRect.new()
	tex.texture = viewport.get_texture()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(tex)
	# 0.31.14 atmosphere: a soft vignette over the 3D view (under the HUD) draws the eye in and deepens the corners.
	var vig := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.08, 1.08)
	var gr := Gradient.new()
	gr.set_color(0, Color(0.05, 0.03, 0.02, 0.0))
	gr.set_color(1, Color(0.05, 0.03, 0.02, 0.32))
	gr.add_point(0.55, Color(0.05, 0.03, 0.02, 0.0))
	gt.gradient = gr
	gt.width = 256
	gt.height = 256
	vig.texture = gt
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vig)
	var t_hud := Time.get_ticks_msec()
	hud = Hud.new()
	hud.diag = diag
	add_child(hud)
	ready_times["hud"] = Time.get_ticks_msec() - t_hud
	hud.leave_requested.connect(func(): exited.emit())
	hud.replay_requested.connect(func():
		if online:
			# 0.31.122 (Kevin: "make it so the game doesn't automatically put player back in a new game because they could be
			# looking at score card"): the server puts us in the next match only now -- when it starts, or at once if it
			# already has (an older server still starts it for everyone on its own). Clear the results screen meanwhile.
			_net_send({"t":"again"})
			again_sent += 1
			if hud.result_panel != null:
				hud.result_panel.queue_free()
				hud.result_panel = null
				if hud.score_panel != null and is_instance_valid(hud.score_panel):   # 0.31.119
					hud.score_panel.queue_free()
				hud.score_panel = null
			hud.toast("Next match starts shortly...", Color("#f2d18d"))
		elif profile != null:
			# 0.31.164: a 5v5 is paid against a ticket of its own -- back through the app (siege_app.start_moba)
			replay_hero = _hero()
			exited.emit()
		else:
			_restart())
	hud.action_pressed.connect(_on_action)
	hud.quick_chat.connect(_on_quick_chat)                 # 0.31.111
	hud.unit_world = func(id: String) -> Vector3: return view.unit_world(id) if view != null else Vector3.INF
	hud.qc_btn.visible = not tutorial
	hud.project = func(world: Vector3) -> Vector2: return _to_hud(view.screen_point(world))
	hud.on_screen = func(world: Vector3) -> bool: return view.is_on_screen(world)
	hud.numbers_source = func() -> Array: return view.numbers if view != null else []
	hud.bars_source = func() -> Array: return view.bars() if view != null else []
	hud.gate_bars_source = func() -> Array: return view.gate_bars() if view != null else []
	hud.numbers_clock = func() -> float: return view._time if view != null else 0.0
	resized.connect(_resize_viewport)
	ready_times["viewport+hud"] = Time.get_ticks_msec() - t_ready - int(ready_times["diag"])
	var t_start := Time.get_ticks_msec()
	if online:
		_start_online()
	elif _staged():
		_start_staged()
	else:
		_start()
	ready_times["start"] = Time.get_ticks_msec() - t_start
	_resize_viewport()
	ready_times["_ready total"] = Time.get_ticks_msec() - t_ready

func _staged() -> bool:
	# The world built over frames behind the loading card (the app); all at once under a scripted main loop (tests and
	# tools expect `sim` right after add_child) unless FB_STAGED_START asks for it.
	return get_tree().get_script() == null or OS.has_environment("FB_STAGED_START")

func _start() -> void:
	for step in _start_steps():
		step.call()

func _start_staged() -> void:
	# 0.31.78 (Kevin: "slow loading into battles"): the loading card goes up on the first frame after PLAY and the match
	# is built behind it, one step per frame (the sim, then the view's parts), so the menu never freezes and the card's
	# dots keep moving. The warm-up camera tour follows as before, and the match clock starts when the card lifts.
	_cover_show()
	_build_queue = _start_steps()

func _start_steps() -> Array:
	# The match's start as steps (each one timed into ready_times / View.build_times).
	var steps := []
	steps.append(func():
		var t_sim := Time.get_ticks_msec()
		sim = Sim.new()
		var seed_value := int(Time.get_unix_time_from_system()) & 0x7fffffff if match_seed < 0 else match_seed
		team_size = 5
		sim.setup(team_size, seed_value)
		sim.setup_moba(_hero(), seed_value)
		ready_times["sim.setup"] = Time.get_ticks_msec() - t_sim
		view = View.new()
		view.low_fx = low_fx
		view.hq_gfx = hq_gfx
		view.player_skins = _skins()                   # 0.31.186 (0.31.188: the outfits are all there is)
		view.my_name = player_name
		view.my_title = my_title()
		view.my_tag = clan_tag
		view.my_crest = clan_crest
		view.tower_broke.connect(_on_tower_broke)
		viewport.add_child(view)
		_view_steps = view.setup_steps(sim))
	# (the view's own steps run from _view_steps between these two: the array is filled by the first step)
	steps.append(_run_view_steps)
	steps.append(func():
		hud.sim = sim
		hud.kill_feed_on = true
		hud.kill_feed = []
		_accum = 0.0
		_result_shown = false
		if analytics != null and not online and not tutorial:
			_an_match = Analytics.hex(4)
			_an_class0 = class_of(sim.by_id.get(hud.player_id, {}))
			analytics.log_ev("match_start", {"match":_an_match, "mode":"5v5", "class":_an_class0})
		_title_reset()
		if tutorial:
			_tutorial_begin())
	return steps

func _hero() -> String:
	# the hero of an offline match (a 5v5 against bots): the one picked, else the Knight
	return moba_hero if moba_hero != "" else "knight"

var _build_queue: Array = []           # steps still to run, one per frame (staged start)
var _view_steps: Array = []

func _run_view_steps() -> void:
	# All of them at once (synchronous start); staged, _process takes them one per frame instead.
	for step in _view_steps:
		step.call()
	_view_steps = []

const BUILD_BUDGET_MS := 20       # steps of the staged start run until a frame has spent this long on them

func _build_step() -> void:
	# Steps of the staged start, as many as fit the frame's budget (the view's steps have their own queue, run before
	# the step after them): never a frozen frame, and no frame spent on a step that took a millisecond.
	var t0 := Time.get_ticks_msec()
	while not _build_queue.is_empty() and Time.get_ticks_msec() - t0 < BUILD_BUDGET_MS:
		if _build_queue[0] == _run_view_steps and not _view_steps.is_empty():
			(_view_steps.pop_front() as Callable).call()
			if not _view_steps.is_empty():
				continue
		(_build_queue.pop_front() as Callable).call()

func _skins() -> Dictionary:
	# 0.31.186: hero -> the skin I wear on him
	return (profile.d.get("skin_on", {}) as Dictionary).duplicate() if profile != null else {}

# ---------- vibration (0.31.120, Kevin: "phone vibration") ----------
# 0.31.128 (Kevin: "I only want phone to vibrate when player makes a kill"): one buzz for each enemy I knock out --
# nothing for being hit, falling, the King, rescues or gates (0.31.120 buzzed for all of those). Settings > VIBRATION.
var vibrate := false        # (the app sets it from Settings; off in tests and tools)
var buzzes := 0             # (tests: how many so far, and the last [ms, strength])
var last_buzz: Array = []
const BUZZ := {"ko": [70, 0.75]}

func _haptic(e: Dictionary) -> void:
	if not vibrate or sim == null:
		return
	var me := str(hud.player_id)
	if str(e.get("k", "")) == "death" and str(e.get("by", "")) == me and str(e.get("id", "")) != me:
		buzz(int(BUZZ.ko[0]), float(BUZZ.ko[1]))

func buzz(ms: int, strength: float) -> void:
	buzzes += 1
	last_buzz = [ms, strength]
	Input.vibrate_handheld(ms, strength)

func _count(e: Dictionary) -> void:
	_haptic(e)
	if str(e.get("id", "")) == hud.player_id and str(e.get("k", "")) == "multikill":
		_best_multi = maxi(_best_multi, int(e.get("n", 0)))
		if _q_cls != "":
			var qe: Dictionary = _q_entry(_q_cls)
			qe["best_multi"] = maxi(int(qe.get("best_multi", 0)), int(e.get("n", 0)))

func my_title() -> String:
	# The title to wear online: the profile's, if it is one the game knows and the player owns.
	if profile == null:
		return ""
	var t := str(profile.d.get("title", ""))
	return t if Net.TITLES.has(t) and profile.owns(t) else ""

func _title_reset() -> void:
	_cls_time = {}
	_kills_cls = {}
	_kills_seen = 0
	_best_multi = 0
	_q = {}
	_q_seen = {}
	_q_cls = ""

func _title_track(delta: float) -> void:
	# Each frame of a match: time as the class you are, and any new knockouts credited to it.
	var me: Dictionary = sim.by_id.get(hud.player_id, {}) if sim != null else {}
	if me.is_empty() or sim.ended:
		return
	var cls := str(me.cls)
	if me.state != "dead":
		_cls_time[cls] = float(_cls_time.get(cls, 0.0)) + delta
	var k := int(me.kills)
	if k > _kills_seen:
		_kills_cls[cls] = int(_kills_cls.get(cls, 0)) + (k - _kills_seen)
		_kills_seen = k
	# 0.31.97: quests -- time as the class worn, and whatever my unit's totals grew by, credited to it
	_q_cls = Eco.cosmetic_class(cls, bool(me.get("up", false)))
	if _q_cls != "" and me.state != "dead":
		var qe: Dictionary = _q_entry(_q_cls)
		qe["t"] = float(qe.get("t", 0.0)) + delta
	for f in Q_UNIT:
		var v := float(me.get(f, 0.0))
		var dv := v - float(_q_seen.get(f, 0.0))
		if dv > 0.0:
			_q_add(str(Q_UNIT[f]), dv)
		_q_seen[f] = v

func title_summary() -> Dictionary:
	# The match's main class: the one played longest (at least a minute of it), else none.
	var main := ""
	var best := 60.0
	for c in _cls_time:
		if float(_cls_time[c]) >= best:
			best = float(_cls_time[c])
			main = str(c)
	var q := {}
	for c in _q:
		var e: Dictionary = _q[c]
		q[c] = {"t": float(e.get("t", 0.0)), "kills": int(e.get("kills", 0.0)),
			"gates": int(float(e.get("gate_dmg", 0.0)) / 100.0), "healed": int(e.get("healed", 0.0)),
			"best_multi": int(e.get("best_multi", 0)), "towers": int(e.get("towers", 0.0)), "camps": int(e.get("camps", 0.0)),
			"lh": int(e.get("lh", 0.0)), "epics": int(e.get("epics", 0.0))}
	return {"cls_main": main, "kills_cls": _kills_cls.duplicate(), "best_multi": _best_multi, "q": q}

func _q_entry(c: String) -> Dictionary:
	if not _q.has(c):
		_q[c] = {}
	return _q[c]

func _q_add(stat: String, n: float) -> void:
	# credit n of a stat to the class I'm wearing
	if _q_cls == "":
		return
	var qe := _q_entry(_q_cls)
	qe[stat] = float(qe.get(stat, 0.0)) + n

func _start_online() -> void:
	ws = WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 20
	ws.outbound_buffer_size = 1 << 16
	var err := ws.connect_to_url(net_url)
	net_state = "connecting"
	_net_started = Time.get_ticks_msec() / 1000.0
	diag.write("NET connect %s err=%d" % [net_url, err])
	hud.toast("Connecting to the server...", Color("#f2d18d"))
	lobby = _loading_screen()
	lobby.leave.connect(func(): exited.emit())
	add_child(lobby)
	if err != OK:
		_net_fail("Could not reach the server")

func _net_fail(why: String) -> void:
	if net_state == "closed":
		return
	net_state = "closed"
	diag.write("NET closed: " + why)
	hud.toast(why, VisualTheme.RED)
	if is_instance_valid(lobby):
		lobby.fail(why)
	if sim == null:
		# Nothing to show: go back home after the message is readable. (A method, not a lambda: the app may free
		# this node first, e.g. for the Update screen, and a freed method target is simply not called.)
		get_tree().create_timer(2.5).timeout.connect(_net_exit)

func _net_exit() -> void:
	if is_inside_tree():
		exited.emit()

func _net_no_five() -> void:
	# 0.31.170: the server answered from before the online 5v5 (not redeployed yet): leave quietly, and Home starts this
	# hero's match against bots instead (siege_app._end_match, exit_note "no_five")
	if net_state == "closed":
		return
	net_state = "closed"
	diag.write("NET the server has no online 5v5: a match against bots instead")
	_net_send({"t":"leave"})
	if ws != null:
		ws.close(1000, "leave")
	exit_note = "no_five"
	replay_hero = _hero()
	_net_exit()

func _net_version_refused(code: int, reason: String) -> bool:
	# A version refusal, from the bye ("need") or the close (code 4001, reason "version:<n>"). Works for every
	# future protocol bump: only Net.VERSION is compared.
	var sv: int = Net.refused_version(_net_bye, code, reason)
	if sv < 0:
		return false
	var verdict: String = Net.version_verdict(sv)
	if verdict == "ok":
		verdict = "server_old"         # refused although the numbers match: treat it as a server mid-update
	net_verdict = verdict
	net_server_version = sv
	diag.write("NET version refused: server %d, client %d -> %s (code %d %s)" % [sv, Net.VERSION, verdict, code, reason])
	version_mismatch.emit(sv, verdict)
	_net_fail(MSG_UPDATE if verdict == "update" else MSG_SERVER_OLD)
	return true

func _net_read_packets() -> Array:
	var out := []
	while ws != null and ws.get_available_packet_count() > 0:
		out.append(Net.decode(ws.get_packet()))
	return out

func _net_send(msg: Dictionary) -> void:
	if ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.put_packet(Net.encode(msg))

func _hello() -> Dictionary:
	var hi := {"t":"hello", "v":Net.VERSION, "name":player_name, "build":Diag.BUILD, "pred":true, "title":my_title(),
		"lk":profile.wire_looks() if profile != null else {}}          # 0.31.101: what I wear, for the others
	if profile != null and bool(profile.server_mode):
		hi["acct"] = str(profile.d.account.id)       # 0.31.108: the server pays this match to the account
		hi["key"] = str(profile.d.account.key)
	hi.merge(Analytics.hello_flags(profile))         # 0.31.118: "an_off" when usage statistics are off
	if party_join != "":
		hi["join"] = party_join                      # 0.31.120: into this friend's match (Friends > JOIN)
	hi["ask_next"] = true                            # 0.31.122: the next match only after PLAY AGAIN (older servers ignore it)
	hi["five"] = Net.FIVE                            # 0.31.170: the online 5v5 -- as my hero (the server checks I own it)
	hi["hero"] = _hero()
	return hi

func _begin_rejoin() -> void:
	# 0.31.120: the connection dropped mid-match -- keep the match on screen and try to get back onto my seat
	net_state = "rejoining"
	_rejoin_until = Time.get_ticks_msec() / 1000.0 + rejoin_for
	_rejoin_at = Time.get_ticks_msec() / 1000.0 + 0.5
	_rejoin_sent = false
	_net_bye = {}
	hud.rejoin_until = _rejoin_until
	diag.write("NET dropped mid-match: reconnecting (token %s...)" % _rj.left(4))

func _rejoin_tick() -> bool:
	# -> true while a new connection is being made (nothing else to read yet)
	var now := Time.get_ticks_msec() / 1000.0
	if now > _rejoin_until:
		hud.rejoin_until = -1.0
		_net_fail("Disconnected from the server")
		return true
	var st := ws.get_ready_state() if ws != null else WebSocketPeer.STATE_CLOSED
	if st == WebSocketPeer.STATE_CLOSED and now >= _rejoin_at:
		_rejoin_at = now + REJOIN_EVERY
		_rejoin_sent = false
		ws = WebSocketPeer.new()
		ws.inbound_buffer_size = 1 << 20
		ws.outbound_buffer_size = 1 << 16
		ws.connect_to_url(net_url)
		_net_started = now
		return true
	if st == WebSocketPeer.STATE_CONNECTING and now - _net_started > 6.0:
		ws.close()
		return true
	return st != WebSocketPeer.STATE_OPEN

func _build_online_match(msg: Dictionary) -> void:
	# A new match (or the first one): rebuild the mirror sim and the 3D view.
	if is_instance_valid(view):
		view.queue_free()
	if hud.result_panel != null:
		hud.result_panel.queue_free()
		hud.result_panel = null
		if hud.score_panel != null and is_instance_valid(hud.score_panel):   # 0.31.119
			hud.score_panel.queue_free()
		hud.score_panel = null
	sim = Sim.new()
	sim.setup(int(msg.get("team_size", Net.TEAM_SIZE)), int(msg.get("seed", 1)), -1)
	sim.setup_moba("", int(msg.get("seed", 1)))      # (0.31.169: the server's 5v5, its heroes drafted from the same seed)
	var me_id := str(msg.get("you", ""))
	hud.player_id = me_id
	view = View.new()
	view.low_fx = low_fx
	view.hq_gfx = hq_gfx
	view.player_id = me_id
	view.player_skins = _skins()                       # 0.31.186
	view.player_names = net_names
	view.player_titles = net_titles
	view.player_tags = net_tags
	view.player_crests = net_crests
	view.set_unit_looks(net_looks)
	view.my_name = player_name
	view.my_title = my_title()
	view.my_tag = clan_tag
	view.my_crest = clan_crest
	view.tower_broke.connect(_on_tower_broke)
	viewport.add_child(view)
	view.setup(sim)
	hud.sim = sim
	hud.kill_feed = []
	net_match = int(msg.get("match", 0))
	hud.rejoin_until = -1.0
	_result_shown = false
	_title_reset()
	net_state = "playing"
	diag.write("NET welcome match=%d you=%s players=%d" % [net_match, me_id, int(msg.get("players", 1))])
	hud.toast("Online: %d player%s" % [int(msg.get("players", 1)), "" if int(msg.get("players", 1)) == 1 else "s"], VisualTheme.GOLD)
	if is_instance_valid(lobby):
		_lobby_to_card()

func _lobby_to_card() -> void:
	# 0.31.208: at the welcome the lobby stays up as the loading card -- the same heroes on the plaza, PREPARING THE
	# BATTLEFIELD (the warm-up keeps it up; tests drop it)
	if _cover != null and _cover != lobby:
		_cover.queue_free()
	lobby.loading()
	_cover = lobby
	lobby = null

func _net_process(delta: float) -> void:
	if ws == null:
		return
	ws.poll()
	var st := ws.get_ready_state()
	if net_state == "rejoining":
		if _rejoin_tick():
			return
		st = ws.get_ready_state()
	if st == WebSocketPeer.STATE_CONNECTING:
		if Time.get_ticks_msec() / 1000.0 - _net_started > 10.0:
			ws.close()
			_net_fail("Server did not answer")
		return
	if st == WebSocketPeer.STATE_CLOSED or st == WebSocketPeer.STATE_CLOSING:
		# A refusal's bye can arrive together with the close: read what is left before deciding (before 0.31.73
		# the state was checked first, so a version refusal only ever said "Could not connect to the server").
		for left in _net_read_packets():
			if str(left.get("t", "")) == "bye":
				_net_bye = left
		if net_state == "closed":
			return
		if st == WebSocketPeer.STATE_CLOSING:
			var now_c := Time.get_ticks_msec() / 1000.0
			if _net_closing_since < 0.0:
				_net_closing_since = now_c
			if now_c - _net_closing_since < 2.0:
				return                         # wait for the close code
		if _net_version_refused(ws.get_close_code(), ws.get_close_reason()):
			return
		if str(_net_bye.get("why", "")) == "full" or ws.get_close_code() == Net.CLOSE_FULL:
			_net_fail("Server is full")
			return
		if str(_net_bye.get("why", "")) == "done":
			_net_exit()                                  # 0.31.122: (the bye and the close arrived together)
			return
		if sim != null and not sim.ended and _rj != "" and net_state == "playing" and _net_bye.is_empty() and ws.get_close_code() != 4006:
			_begin_rejoin()                              # 0.31.120: the connection dropped -- try to get back in
			return
		_net_fail("Disconnected from the server" if sim != null else "Could not connect to the server")
		return
	if net_state == "connecting":
		net_state = "waiting"
		_net_send(_hello())
	if net_state == "rejoining" and not _rejoin_sent:
		_rejoin_sent = true
		var hr := _hello()
		hr["rj"] = _rj                                   # 0.31.120: back onto my seat
		_net_send(hr)
	while ws.get_available_packet_count() > 0:
		var msg := Net.decode(ws.get_packet())
		match str(msg.get("t", "")):
			"welcome":
				if int(msg.get("five", 0)) < Net.FIVE:
					_net_no_five()                              # 0.31.170: a server from before the online 5v5
					return
				_rj = str(msg.get("rj", _rj))                   # 0.31.120: my seat's token, for a rejoin
				if bool(msg.get("rejoin", false)) and int(msg.get("match", -1)) == net_match and sim != null:
					net_state = "playing"
					rejoins += 1
					hud.rejoin_until = -1.0
					_net_rt = -1.0                              # (the render clock starts again from the next snapshot)
					_net_rx_last = 0.0
					hud.toast("Back in the match!", Color("#8fe3a2"))
					diag.write("NET rejoined match %d as %s" % [net_match, str(msg.get("you", ""))])
				elif int(msg.get("match", -1)) != net_match:
					_build_online_match(msg)
					var got := str(msg.get("hero", ""))
					if got != "" and got != _hero() and Moba.HEROES.has(got):
						# 0.31.170: someone on my side plays my pick, or the server doesn't know I bought it yet
						hud.toast("%s was taken -- you're the %s" % [str(Moba.HEROES.get(_hero(), {}).get("name", _hero())),
							str(Moba.HEROES[got].name)], Color("#f2d18d"))
			"s":
				if sim == null:
					continue
				Net.apply(sim, msg, hud.player_id, not _me_bot)
				var was_bot := _me_bot
				_me_bot = bool(sim.by_id.get(hud.player_id, {}).get("bot", false))
				if was_bot and not _me_bot:
					hud.idle_kick_at = -1.0                # (mine again)
				_snap_dt = lerpf(_snap_dt, maxf(0.03, _snap_t), 0.2) if _snap_t > 0.0 else _snap_dt
				_snap_t = 0.0
				_net_latest = float(msg.get("tm", _net_latest))
				# 0.31.24: the draw delay adapts to the connection -- the gap between arrivals vs the snapshot interval
				var now_rx := Time.get_ticks_msec() / 1000.0
				if _net_rx_last > 0.0:
					var gap := now_rx - _net_rx_last
					_net_jitter = lerpf(_net_jitter, absf(gap - 1.0 / Net.SNAP_HZ), 0.1)
				_net_rx_last = now_rx
				_net_delay = clampf(Net.INTERP_DELAY + 1.5 * _net_jitter, Net.INTERP_DELAY, 0.25)
				if _net_rt < 0.0:
					_net_rt = _net_latest - _net_delay
				for e in msg.get("e", []):
					diag.event()
					_count(e)
					# an effect of my own that I already showed when I pressed the button: don't show it twice
					if str(e.get("id", "")) == hud.player_id and _pred_fx.has(str(e.k)) and Time.get_ticks_msec() / 1000.0 - float(_pred_fx[str(e.k)]) < 0.6:
						_pred_fx.erase(str(e.k))
						hud.on_event(e)
						continue
					view.on_event(e)
					_event_sound(e)
					hud.on_event(e)
			"lobby":                                          # 0.31.82: waiting for the wave's countdown
				if int(msg.get("five", 0)) < Net.FIVE:
					_net_no_five()                              # 0.31.170: a server from before the online 5v5
					return
				lobby_msgs += 1
				if lobby_msgs == 1:
					diag.write("NET lobby left=%.1f names=%d online=%d running=%s" % [float(msg.get("left", 0)), (msg.get("names", []) as Array).size(), int(msg.get("online", 0)), str(msg.get("running", false))])
				if sim == null and is_instance_valid(lobby):
					lobby.update(msg)
			"pn":                                             # 0.31.86: the live players' names, by unit
				var pn: Variant = msg.get("n", {})
				net_names = pn if pn is Dictionary else {}
				var tt: Variant = msg.get("tt", {})
				net_titles = tt if tt is Dictionary else {}
				var lk: Variant = msg.get("lk", {})           # 0.31.101: what each of them wears
				net_looks = lk if lk is Dictionary else {}
				var ct: Variant = msg.get("ct", {})           # 0.31.134: their clan tags
				net_tags = ct if ct is Dictionary else {}
				var cc: Variant = msg.get("cc", {})           # 0.31.196: and crests
				net_crests = cc if cc is Dictionary else {}
				hud.net_names = net_names                     # 0.31.119: the scoreboard names the players
				if is_instance_valid(view):
					view.player_names = net_names
					view.player_titles = net_titles
					view.player_tags = net_tags
					view.player_crests = net_crests
					view.set_unit_looks(net_looks)
			"qc":                                             # 0.31.111: a quick chat line from a player of my side (or anyone's gg)
				var qu := str(msg.get("u", ""))
				if qu != hud.player_id and sim != null:      # (mine showed when I said it)
					hud.add_ping(qu, int(msg.get("i", -1)), str(net_names.get(qu, "")))
					_ping_sound()
			"st":                                             # 0.31.87: the health I've healed (the Merciful title)
				if sim != null and sim.by_id.has(hud.player_id):
					sim.by_id[hud.player_id]["healed"] = float(msg.get("heal", 0))
			"m":                                              # 0.31.23: my task, sent on its own when it changes
				if sim != null and sim.by_id.has(hud.player_id):
					sim.by_id[hud.player_id].task = msg.get("task", {})
			"joinr":                                          # 0.31.120: the friend's match couldn't take me
				var jw := str(msg.get("why", ""))
				hud.toast("Their match is full -- you're in another one" if jw == "full" else "They've left that match -- you're in another one", Color("#f2d18d"))
				if is_instance_valid(lobby) and lobby.has_method("note"):
					lobby.note("Their match is full" if jw == "full" else "They've left that match")
			"idle":                                           # 0.31.119: a bot plays for me until I move (or I'm removed)
				if bool(msg.get("on", false)):
					hud.idle_kick_at = Time.get_ticks_msec() / 1000.0 + float(msg.get("kick_in", 120.0))
				else:
					hud.idle_kick_at = -1.0
			"bye":
				_net_bye = msg
				if _net_version_refused(-1, ""):
					return
				var why := str(msg.get("why", ""))
				if why == "done":
					_net_exit()                             # 0.31.122: left on the results a long while -- back to Home
					return
				if why == "idle":
					exit_note = "idle"
					_net_fail("Removed for being idle")
					get_tree().create_timer(2.5).timeout.connect(_net_exit)     # (back to Home, which says why)
					return
				_net_fail({"full":"Every match is full -- try again in a minute"}.get(why, "Server closed the connection"))
				return
	if sim == null:
		return
	_snap_t += delta
	# 0.31.23: a render clock in server time, INTERP_DELAY behind the newest snapshot, eased so jitter doesn't show
	if _net_rt >= 0.0:
		_net_rt += delta
		var want := _net_latest - _net_delay
		var err := want - _net_rt
		if absf(err) > 0.3:
			_net_rt = want
		else:
			_net_rt += err * minf(1.0, delta * 3.0)
		Net.interpolate_at(sim, _net_rt, "" if _me_bot else hud.player_id)     # (a bot playing me: drawn like the others)
	# Inputs: movement and held attack at 20 Hz (or when they change); actions go immediately.
	_send_clock += delta
	var mv: Vector2 = _move_input() if not hud.paused() else Vector2.ZERO
	var hold: bool = hud.attack_held() and not hud.paused()
	var bhold: bool = hud.ability_held() and not hud.paused()
	# Client-side prediction: move our own unit now (same movement code as the server); the server
	# validates the position we send. Snapshots only correct us when we've drifted > 2.5 m.
	var me_p: Dictionary = sim.by_id.get(hud.player_id, {})
	if not me_p.is_empty() and not _me_bot and sim.client_drivable(me_p):
		sim.predict_step(me_p, mv, delta)
		# Held ATTACK: the server swings every time it can; start the same swings locally.
		if hold and me_p.cls != "priest" and sim.can_act(me_p):
			sim._start_attack(me_p, "attack")
		sim.drain_events()                         # (prediction events are shown in _act; nothing else should pile up)
	if _send_clock >= 0.05 or (mv - _sent_move).length() > 0.25 or hold != _sent_hold or bhold != _sent_bhold:
		_send_clock = 0.0
		_sent_move = mv
		_sent_hold = hold
		_sent_bhold = bhold
		var msg_in := {"t":"in", "m":mv, "h":hold, "b":bhold}
		if not me_p.is_empty() and not _me_bot:
			msg_in["p"] = me_p.pos
			msg_in["f"] = me_p.face
		_net_send(msg_in)

func _move_input() -> Vector2:
	# The stick in world terms. 0.31.85 (Kevin: "When on the other team ... controls are inverted"): the camera looks up
	# the field from your own castle, so on the red team (online) it is turned half way round from blue's -- the
	# stick's screen directions are the opposite world directions there.
	var v: Vector2 = hud.move_vector()
	if sim != null and int(sim.by_id.get(hud.player_id, {}).get("team", 0)) == 1:
		v = -v
	return v

func _restart() -> void:
	if is_instance_valid(view):
		view.queue_free()
	if hud.result_panel != null:
		hud.result_panel.queue_free()
		hud.result_panel = null
		if hud.score_panel != null and is_instance_valid(hud.score_panel):   # 0.31.119
			hud.score_panel.queue_free()
		hud.score_panel = null
	if _staged():
		_warm_done = false                 # the card again (briefly: the pipelines are compiled by now)
		_start_staged()
	else:
		_start()

func _resize_viewport() -> void:
	# The canvas transform is 1.0 under canvas_items stretching, so it can't tell logical from
	# physical pixels (that bug rendered 3D at 336x746 on a 1440x3200 screen). Use the real
	# window size over the logical viewport size instead.
	var logical := get_viewport().get_visible_rect().size
	var window := Vector2(DisplayServer.window_get_size())
	var phys := window / logical if logical.x > 0.0 and window.x > 0.0 else Vector2.ONE
	var scale := phys * render_scale
	viewport.size = Vector2i(maxi(64, int(size.x * scale.x)), maxi(64, int(size.y * scale.y)))
	# At native density MSAA costs bandwidth for no visible gain; keep it for reduced scales.
	viewport.msaa_3d = Viewport.MSAA_DISABLED if render_scale >= 0.99 else Viewport.MSAA_2X
	if diag != null:
		diag.write("3D RES %dx%d = %d%% of window %dx%d (logical %dx%d, refresh %.0f Hz, fps cap %d)" % [viewport.size.x, viewport.size.y,
			int(render_scale * 100.0), int(window.x), int(window.y), int(size.x), int(size.y), DisplayServer.screen_get_refresh_rate(), fps_cap])

func set_render_scale(v: float) -> void:
	render_scale = clampf(v, 0.25, 1.0)
	_resize_viewport()

func _to_hud(p: Vector2) -> Vector2:
	var vs := Vector2(viewport.size)
	return p * (size / vs) if vs.x > 0 else p

func _act(action: String, arg: Variant = null) -> void:
	if online:
		var me_a: Dictionary = sim.by_id.get(hud.player_id, {})
		if action in ["dodge", "attack"] and not me_a.is_empty() and sim.client_drivable(me_a):
			# Predict dodges and swings locally: the animation starts now, the server resolves the hit.
			if action == "dodge":
				sim._dodge(me_a)
			elif me_a.cls != "priest":
				sim._start_attack(me_a, "attack")
		elif action == "ability" and not me_a.is_empty() and sim.client_drivable(me_a) and not me_a.has("kq"):
			# (0.31.170: not a new hero's Q -- a kit spell only the server casts)
			# 0.31.23 (Kevin: "abilities lag"): the ability's start shows now -- the swing, the spin, the ring; the
			# server resolves what it does (the predicted start happens in _process right after this frame's input)
			if sim.predict_ability(me_a):
				for e in sim.drain_events():
					_pred_fx[str(e.k)] = Time.get_ticks_msec() / 1000.0
					view.on_event(e)
					_event_sound(e)
		var msg_a := {"t":"in", "m":_move_input(), "h":hud.attack_held(), "b":hud.ability_held(), "k":hud.block_held(), "a":action, "arg":arg}
		if not me_a.is_empty():
			msg_a["p"] = me_a.pos
			msg_a["f"] = me_a.face
		_net_send(msg_a)
		return
	sim.act(hud.player_id, action, arg)

func _on_action(kind: String) -> void:
	if online and kind not in ["attack", "ability", "dodge"]:
		_on_action_online(kind)
		return
	match kind:
		"attack": _act("attack")
		"ability":
			var me_q: Dictionary = sim.by_id.get(hud.player_id, {}) if sim != null else {}
			if sim != null and not me_q.is_empty() and me_q.has("kq") and not online:
				# 0.31.168: a new hero's Q is a kit spell -- say why when it can't go (CHAIN, ROOTS need someone near)
				if not sim.act(hud.player_id, "ability") and float(me_q.get("cd_ability", 0.0)) <= 0.0 and sim.can_act(me_q):
					hud.toast("No enemy in reach", Color("#ffcf7a"))
			else:
				_act("ability")
		"dodge": _act("dodge")
		"pick0", "pick1", "pick2":                       # 0.31.155 5V5: a level-up choice
			if sim != null and sim.act(hud.player_id, "pick", int(kind.right(1))):
				if audio != null and audio.has_method("play"):
					audio.play("equip")
		"ult":                                           # 0.31.157 5V5: the ultimate
			if sim != null and not sim.act(hud.player_id, "ult"):
				var me_u: Dictionary = sim.by_id.get(hud.player_id, {})
				if not me_u.is_empty() and sim.moba.ult_rank(me_u) == 0:
					hud.toast("Your ultimate comes at level %d" % sim.moba.ULT_LEVEL, Color("#ffcf7a"))
				elif not me_u.is_empty() and float(me_u.get("ult_cd", 0.0)) <= 0.0 and sim.can_act(me_u):
					hud.toast("No enemy in reach", Color("#ffcf7a"))         # (EXECUTE, FLURRY: they need someone near)
		"w", "e":                                        # 0.31.167 5V5: W and E
			if sim != null and not sim.act(hud.player_id, "spell", kind):
				var me_s: Dictionary = sim.by_id.get(hud.player_id, {})
				if not me_s.is_empty() and not sim.moba.kits.unlocked(me_s, kind):
					hud.toast("%s comes at level %d" % [kind.to_upper(), int(sim.moba.kits.UNLOCK[kind])], Color("#ffcf7a"))
				elif not me_s.is_empty() and float(me_s.get("cd_" + kind, 0.0)) <= 0.0 and sim.can_act(me_s):
					hud.toast("No enemy hero in reach", Color("#ffcf7a"))       # (SHADOW STEP, MARK, CURSE need one)
		"recall":                                        # 0.31.181: home to the fountain
			if sim != null:
				var me_r: Dictionary = sim.by_id.get(hud.player_id, {})
				if sim.act(hud.player_id, "recall"):
					pass                                     # (its sound comes with its event)
				elif not me_r.is_empty() and sim.alive(me_r) and not sim.recalling(me_r):
					hud.toast("You're home already" if (me_r.pos as Vector2).distance_to(sim.spawn(int(me_r.team))) < 8.0 else "Can't recall right now", Color("#ffcf7a"))
		"ward":                                          # 0.31.158 5V5: a ward at your feet
			if sim != null:
				if sim.act(hud.player_id, "ward"):
					if audio != null and audio.has_method("play"):
						audio.play("equip")
				else:
					hud.toast("No ward charge yet", Color("#ffcf7a"))
		_:
			if kind.begins_with("shop_buy:") or kind.begins_with("shop_sell:"):     # 0.31.157 5V5: the shop
				var ok: bool = sim != null and sim.act(hud.player_id, "shop_buy" if kind.begins_with("shop_buy:") else "shop_sell",
					kind.get_slice(":", 1) if kind.begins_with("shop_buy:") else int(kind.get_slice(":", 1)))
				if audio != null and audio.has_method("play"):
					audio.play("purchase" if ok and kind.begins_with("shop_buy:") else ("coin" if ok else "error"))

func _on_action_online(kind: String) -> void:
	# 0.31.170: the 5v5's buttons online -- the server does it (the next snapshots show it); here only what my copy of the
	# match can already tell: the same toasts and sounds as against bots when it can't be done, and the sound when it can
	var me: Dictionary = sim.by_id.get(hud.player_id, {}) if sim != null else {}
	if me.is_empty() or sim.ended:
		return
	var play := func(cue: String) -> void:
		if audio != null and audio.has_method("play"):
			audio.play(cue)
	match kind:
		"pick0", "pick1", "pick2":
			var picks: Array = me.get("picks", [])
			if picks.is_empty() or not sim.alive(me):
				return                                   # (down: the server wouldn't take it, as against bots)
			picks.pop_front()                            # (shown at once; the server's count follows)
			_act("pick", int(kind.right(1)))
			play.call("equip")
		"ult":
			if sim.moba.ult_rank(me) == 0:
				hud.toast("Your ultimate comes at level %d" % sim.moba.ULT_LEVEL, Color("#ffcf7a"))
			elif float(me.get("ult_cd", 0.0)) <= 0.0 and sim.can_act(me):
				_act("ult")
		"w", "e":
			if not sim.moba.kits.unlocked(me, kind):
				hud.toast("%s comes at level %d" % [kind.to_upper(), int(sim.moba.kits.UNLOCK[kind])], Color("#ffcf7a"))
			elif float(me.get("cd_" + kind, 0.0)) <= 0.0 and sim.can_act(me):
				_act("spell", kind)
		"recall":                                        # 0.31.181
			if sim.alive(me) and not sim.recalling(me) and sim.can_act(me):
				_act("recall")
		"ward":
			if sim.moba.vision.ward_ready(me):
				_act("ward")
				play.call("equip")
			else:
				hud.toast("No ward charge yet", Color("#ffcf7a"))
		_:
			if kind.begins_with("shop_buy:"):
				var id := kind.get_slice(":", 1)
				var ok: bool = sim.moba.buy_why(me, id) == ""
				if ok:
					_act("shop_buy", id)
				play.call("purchase" if ok else "error")
			elif kind.begins_with("shop_sell:"):
				var slot := int(kind.get_slice(":", 1))
				var ok2: bool = sim.moba.can_shop(me) and slot >= 0 and slot < (me.get("items", []) as Array).size()
				if ok2:
					_act("shop_sell", slot)
				play.call("coin" if ok2 else "error")

# ---- Warm-up cover (Round 16, Kevin: the 3D world showed black for a few seconds at match start: the
# phone compiling the scene's shader pipelines). A loading card covers the first moments while the
# camera visits the key places so their materials compile behind it; it lifts once the engine's
# pipeline-compilation counters have been still for WARM_STILL (never before WARM_MIN, at most
# WARM_MAX). Offline the match clock waits. Skipped under scripted main loops (tests, render tools).
# 0.31.208: the card is the loading screen (loading_screen.gd: the heroes on the plaza), not the castle wall's.
const WARM_MIN := 0.6
const WARM_MAX := 10.0
const WARM_STILL := 0.5
var _warm: Dictionary = {}
var _warm_done := false
var warm_max := WARM_MAX                   # (tools/hitch_bench.gd: longer, for a desktop's software renderer)
var _cover: Control = null             # 0.31.208: the loading screen (loading_screen.gd), as the card
var _cover_t := 0.0

func _loading_screen() -> Control:
	# 0.31.208: the loading screen, with my hero on its plaza in the outfit I wear on him
	var ls: Control = Loading.new()
	ls.audio = audio
	ls.my_hero = _hero()
	ls.my_skin = str(_skins().get(_hero(), ""))
	ls.my_name = ("[%s] " % clan_tag if clan_tag != "" else "") + Net.title_text(player_name, my_title())
	return ls

func _cover_show() -> void:
	# The loading card over everything (the staged start builds the world behind it; the warm-up keeps it up).
	# 0.31.208: the loading screen (loading_screen.gd) in its loading state; the card on the castle wall until then.
	if _cover != null:
		return
	var ls := _loading_screen()
	ls.loading()
	add_child(ls)
	_cover = ls

func _cover_tick(delta: float) -> void:
	_cover_t += delta                  # (the loading screen moves its own dots)

func _warm_begin() -> void:
	_warm_done = true
	if get_tree().get_script() != null and not OS.has_environment("FB_FORCE_WARMUP"):
		if _cover != null:
			_cover.queue_free()
			_cover = null
		return
	_cover_show()
	var spots := []
	for t in 2:
		for q in [Keep.C, Keep.FOUNTAIN, Keep.gate_c(1) + Vector2(0.0, -6.0)]:      # (0.31.165: the keeps)
			spots.append(Sim._m(t, q))
	spots.append(Vector2.ZERO)
	_warm = {"cover": _cover, "t": 0.0, "last": -1, "still": 0.0, "spots": spots, "i": 0, "fade": -1.0, "fx": [], "pool": [], "fight": [], "shown": []}

func _warm_step(delta: float) -> bool:
	# True while the match should wait behind the cover.
	var w := _warm
	w.t = float(w.t) + delta
	var spots: Array = w.spots
	var i := int(w.i)
	if i < spots.size() * 2:
		var p: Vector2 = spots[i / 2]
		var y := Sim.height_at(p)
		view.cam_override = [Vector3(p.x + 6.0, y + 16.0, p.y + 10.0), Vector3(p.x, y, p.y)]
		w.i = i + 1
	elif i == spots.size() * 2:
		view.cam_override = []
		view.snap_camera()
		w.i = i + 1
		# 0.31.207 (Kevin: "The match keeps getting stutters"): with the camera on you, every look of this match's heroes
		# once (spell_fx.warm_jobs), then a wave's minion bodies into the view's pool (prefill_minions)
		if view.fxs != null:
			w.fx = view.fxs.warm_jobs(hud.player_id)
		if sim.moba != null:
			(w.fx as Array).append_array(view.warm_bodies(hud.player_id))
			w.pool = view.prefill_minions({"melee":6, "caster":6, "siege":1})     # (two waves' worth: they overlap)
			w.fight = view.warm_fight()                                       # (after: a pooled body falls)
	else:
		# a look a frame and the pool's bodies four a frame, then the fight (on a pooled body); what the view itself
		# makes for a look (smoke, blasts, roots, numbers) is noted, to hide when the card lifts
		var pool: Array = w.pool
		for k in 4:
			if not pool.is_empty():
				(pool.pop_front() as Callable).call()
		var list: Array = w.fx if not (w.fx as Array).is_empty() else (w.fight if pool.is_empty() else [])
		if not list.is_empty():
			var shown: Array = w.shown
			var grab := func(n: Node): shown.append(n)
			view.child_entered_tree.connect(grab)
			(list.pop_front() as Callable).call()
			view.child_entered_tree.disconnect(grab)
	var c := 0
	for k in [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]:
		c += RenderingServer.get_rendering_info(k)
	if c != int(w.last):
		w.last = c
		w.still = 0.0
	else:
		w.still = float(w.still) + delta
	_cover_tick(delta)
	var cover: Control = w.cover
	if float(w.fade) < 0.0:
		var jobs_done: bool = (w.fx as Array).is_empty() and (w.pool as Array).is_empty() and (w.fight as Array).is_empty()
		if (int(w.i) > spots.size() * 2 and jobs_done and float(w.t) >= WARM_MIN and float(w.still) >= WARM_STILL) or float(w.t) >= warm_max:
			w.fade = 0.0
			diag.mark("warm-up %.1f s, %d pipeline compiles, %d looks shown, %d bodies pooled%s" % [float(w.t), c,
				int(view.fxs.warm_shown) if view.fxs != null else 0, view.pool_size(), "" if jobs_done else " (cut short)"])
			_warm_clear()
		return true
	w.fade = float(w.fade) + delta
	cover.modulate.a = clampf(1.0 - float(w.fade) / 0.3, 0.0, 1.0)
	if float(w.fade) >= 0.3:
		cover.queue_free()
		_cover = null
		_warm = {}
		return false
	return float(w.fade) < 0.15

func _warm_clear() -> void:
	# the warm-up's looks gone before the match is seen (the view's own go on their timers, hidden till then)
	if is_instance_valid(view) and view.fxs != null:
		view.fxs.clear_all()
	if is_instance_valid(view):
		view.warm_end()
	for n in _warm.get("shown", []):
		if is_instance_valid(n) and n is Node3D and not view.proj_nodes.values().has(n):
			(n as Node3D).visible = false
	_warm["fx"] = []
	_warm["pool"] = []
	_warm["fight"] = []

func _process(delta: float) -> void:
	if not _build_queue.is_empty():
		_cover_tick(delta)
		_build_step()                      # the staged start: one step per frame behind the card
		if not _build_queue.is_empty():
			return
		diag.mark("built")
		diag.write("MATCH BUILT ready=%s build=%s" % [str(ready_times), str(View.build_times)])
	_ann_clock += delta
	_announce_tick()
	if online:
		_net_process(delta)
	if sim == null:
		return
	if not _warm_done:
		_warm_begin()
	if not _warm.is_empty() and _warm_step(delta):
		view.proj_lead = 0.0
		view.sync(delta)
		return
	diag.mark("input")
	_footsteps(delta)
	_title_track(delta)
	_ambience(delta)
	var t_start := Time.get_ticks_usec()
	if online:
		pass   # the server steps the match; _net_process applied the latest snapshot
	elif (not hud.paused() and (tutorial_ui == null or not tutorial_ui.holds())) or sim.ended:
		sim.set_move(hud.player_id, _move_input())
		var me_b: Dictionary = sim.by_id.get(hud.player_id, {})
		if hud.ability_held() and not me_b.is_empty() and sim.ability_of(me_b) == "block":
			sim.act(hud.player_id, "ability")
		if hud.block_held() and not me_b.is_empty():
			sim.act(hud.player_id, "block")
		if hud.attack_held():
			var me: Dictionary = sim.by_id[hud.player_id]
			if sim.can_act(me):
				sim.act(hud.player_id, "attack")
		_accum += minf(delta, 0.1)
		diag.mark("sim.step")
		var t_sim := Time.get_ticks_usec()
		while _accum >= Sim.TICK:
			_accum -= Sim.TICK
			sim.step(Sim.TICK)
		diag.add_time("sim", Time.get_ticks_usec() - t_sim)
		for e in sim.drain_events():
			diag.mark("event " + str(e.k))
			diag.event()
			_count(e)
			view.on_event(e)
			hud.on_event(e)
			_event_sound(e)
			if tutorial_ui != null:
				tutorial_ui.on_event(e)
	diag.mark("view.sync")
	view.proj_lead = 0.0 if online else _accum          # online, projectiles interpolate (Net)
	var t_view := Time.get_ticks_usec()
	view.sync(delta)
	diag.add_time("view", Time.get_ticks_usec() - t_view)
	diag.mark("process done")
	diag.add_time("game", Time.get_ticks_usec() - t_start)
	if sim.ended and not _result_shown:
		_result_shown = true
		diag.write("MATCH END winner=%d reason=%s score=%s" % [sim.winner, sim.end_reason, str(sim.score)])
		var me: Dictionary = (sim.by_id[hud.player_id] as Dictionary).duplicate()
		me.merge(title_summary(), true)
		var won: bool = sim.winner == int(me.team)
		var draw: bool = sim.winner == -1
		match_result = {}
		if profile != null:
			match_result = profile.apply_match(me, won, draw, online)
			rewards = match_result.rewards
		diag.write("REWARDS %s" % str(match_result.get("rewards", {}).get("gold", 0)))
		hud.player_name = player_name
		hud.show_result(match_result)
		_result_sounds(won, draw)
		if analytics != null and not online and _an_match != "":
			analytics.log_ev("match_finish", {"match":_an_match, "mode":"5v5", "dur_s":int(sim.time),
				"result":"win" if won else ("draw" if draw else "loss"), "team_n":1, "class":class_of(me), "class0":_an_class0})

func _result_sounds(won: bool, draw: bool) -> void:
	# 0.31.110 (Kevin: "more menu sound effects"): the results' stinger -- brass and drums for a win, low strings and a
	# horn for a loss (softly for a draw) -- then, once it's played out, a level up's arpeggio or a pass tier's chime
	if audio == null or not audio.has_method("play"):
		return
	audio.play("resultWin" if won else "resultLose", draw and not won)
	var next := ""
	if not (match_result.get("levels", []) as Array).is_empty():
		next = "levelUp"
	elif not (match_result.get("tiers", []) as Array).is_empty():
		next = "tierUp"
	if next != "":
		get_tree().create_timer(1.6).timeout.connect(_late_cue.bind(next))

func _late_cue(cue: String) -> void:
	if audio != null and audio.has_method("play"):
		audio.play(cue)

# ---------- the tutorial (0.31.181) ----------
func warmed() -> bool:
	# the match is built and its warm-up cover is gone (the Herald waits for it)
	return _warm_done and _warm.is_empty() and _build_queue.is_empty()

func tutorial_pays() -> bool:
	# its gold is still to come (Profile.finish_tutorial pays it once: Siege's tutorial before 0.31.164 counted)
	return profile != null and not bool(profile.d.get("tutorial_done", false))

func _tutorial_begin() -> void:
	tutorial_ui = Tutorial.new()
	tutorial_ui.name = "Tutorial"
	hud.add_child(tutorial_ui)
	hud.move_child(tutorial_ui, 1)       # over the HUD's drawing, under its pause button, panels and banners
	tutorial_ui.begin(self)
	_tut_t0 = Time.get_ticks_msec()
	if analytics != null:
		analytics.log_ev("tutorial_start", {})

func finish_tutorial() -> void:
	# the Herald's last line tapped: the recruit's pay (once ever), and home
	if _tut_done:
		return
	_tut_done = true
	var paid := false
	if profile != null:
		paid = bool(profile.finish_tutorial().get("ok", false))
	exit_note = "tutorial_paid" if paid else "tutorial"
	if analytics != null:
		analytics.log_ev("tutorial_complete", {"dur_s":(Time.get_ticks_msec() - _tut_t0) / 1000})
	exited.emit()

static func class_of(u: Dictionary) -> String:
	# 0.31.118: the class a unit plays, its upgrade marked ("knight", "knight+") -- as the server writes it
	return str(u.get("cls", "")) + ("+" if bool(u.get("up", false)) else "")

func note_leaving() -> void:
	# 0.31.118: the app is taking us down -- a VS BOTS match left before its end
	if analytics == null:
		return
	if tutorial and not _tut_done and tutorial_ui != null:
		analytics.log_ev("tutorial_skip", {"dur_s":(Time.get_ticks_msec() - _tut_t0) / 1000, "step":int(tutorial_ui.step),
			"id":str(tutorial_ui.STEPS[int(tutorial_ui.step)].id)})
	if not online and _an_match != "" and sim != null and not sim.ended:
		analytics.log_ev("match_quit", {"match":_an_match, "mode":"bots", "quit_at_s":int(sim.time),
			"class":class_of(sim.by_id.get(hud.player_id, {})), "class0":_an_class0})

func set_fps_cap(v: int) -> void:
	fps_cap = v
	Engine.max_fps = v
	if diag != null:
		diag.write("FPS CAP %d" % v)

func _exit_tree() -> void:
	Engine.max_fps = _prev_max_fps
	Engine.physics_ticks_per_second = _prev_physics_tps
	if ws != null:
		_net_send({"t":"leave"})            # 0.31.120: quitting on purpose -- the server doesn't hold the seat
		ws.close(1000, "leave")
		var closer := SocketCloser.new()   # (polled until the close is out: this node is about to go)
		closer.ws = ws
		if is_inside_tree():
			get_tree().root.add_child.call_deferred(closer)

class SocketCloser extends Node:
	# 0.31.120: keeps polling a closing socket for a moment so its "leave" and close frame reach the server
	var ws: WebSocketPeer
	var t := 0.0
	func _process(delta: float) -> void:
		t += delta
		ws.poll()
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED or t > 3.0:
			queue_free()

func request_leave() -> void:
	# Android back button: open the pause panel rather than quitting a match outright.
	if sim == null:
		exited.emit()                      # (0.31.82: still in the lobby -- nothing to pause)
	elif hud.result_panel != null:
		exited.emit()
	else:
		hud.show_pause()
		hud._center(hud.pause_panel)


# ---------------- match sound (0.30.8: TomMusic "Free Fantasy SFX Pack", royalty-free; the hammer is ElevenLabs) ----
# Every sound is placed: full volume within 6 m of you, fading out by HEAR_R (big events carry further), so 32
# units fighting across the map don't drown out what's next to you. Variants are picked at random.
const HEAR_R := 24.0
var _snd_rng := RandomNumberGenerator.new()
var _step_t := 0.0
var _step_last := Vector2.INF
var _amb := {}
# Match music (0.30.9): the trailers' song, looping at a steady, quiet level under everything (Kevin: no dipping;
# quiet enough not to drown out other sound). Only the Music slider moves it.
const MUSIC_PATH := "res://assets/music/match.ogg"
const MUSIC_GAIN := 0.064         # x master x music (0.045 until 0.30.11, Kevin: "just a bit louder": +3 dB); track at -16 LUFS
var _music: AudioStreamPlayer = null

func _listener() -> Vector2:
	var me: Dictionary = sim.by_id.get(str(hud.player_id), {})
	if not me.is_empty():
		return me.pos
	return _step_last if _step_last != Vector2.INF else Vector2.ZERO

# 0.31.167: each W/E's sound -- [cue, takes, gain]. 0.31.171 (step 3, hero polish): every one its own (tools/
# build_hero_sfx.py, "ab_<spell>"); a spell that lands a moment later (FIRE PILLAR, ENTANGLE) or answers a blow
# (RIPOSTE) keeps a light cast and has its own sound where it lands ("pillar", "burst", "riposte").
const SPELL_CUE := {"bash":["ab_bash", 1, 1.0], "rally":["ab_rally", 1, 1.0], "consecrate":["ab_consecrate", 1, 1.0],
	"leap":["ab_leap", 1, 1.0], "bloodlust":["ab_bloodlust", 1, 1.0], "charge":["ab_charge", 1, 1.0],
	"frenzy":["ab_frenzy", 1, 1.0], "caltrops":["ab_caltrops", 1, 1.0], "poison":["ab_poison", 1, 1.0],
	"shadowstep":["ab_shadowstep", 1, 1.0], "knives":["ab_knives", 1, 1.0], "tumble":["ab_tumble", 1, 1.0],
	"snare":["ab_snare", 1, 1.0], "trap":["ab_trap", 1, 1.0], "mark":["ab_mark", 1, 1.0],
	"pillar":["tm_firespray", 2, 0.5], "blink":["ab_blink", 1, 1.0], "missiles":["ab_missiles", 1, 1.0],
	"manashield":["ab_manashield", 1, 1.0], "holylight":["ab_holylight", 1, 1.0], "dazzle":["ab_dazzle", 1, 1.0],
	"boneshield":["ab_boneshield", 1, 1.0], "curse":["ab_curse", 1, 1.0],
	# 0.31.168: the six new heroes
	"boulder":["ab_boulder", 1, 1.0], "stoneskin":["ab_stoneskin", 1, 1.0], "quake":["ab_quake", 1, 1.0],
	"sweep":["ab_sweep", 1, 1.0], "impale":["ab_impale", 1, 1.0], "vault":["ab_vault", 1, 1.0],
	"thrust":["ab_thrust", 1, 1.0], "riposte":["tm_sword_block", 3, 0.8], "feint":["ab_feint", 1, 1.0],
	"chain":["ab_chain", 1, 1.0], "static":["ab_static", 1, 1.0], "gust":["ab_gust", 1, 1.0],
	"buckshot":["ab_buckshot", 1, 1.0], "keg":["ab_keg", 1, 1.0], "smokeroll":["ab_smokeroll", 1, 1.0],
	"rejuv":["ab_rejuv", 1, 1.0], "entangle":["tm_crumble", 2, 0.4], "barkskin":["ab_barkskin", 1, 1.0]}
# 0.31.171: the new heroes' basic attacks and their hits (by HERO_SHOT, and the Golem's stone hammer)
const SHOT_CUE := {"ball":"atk_musket", "bolt":"atk_bolt", "thorn":"atk_thorn"}
const HIT_CUE := {"musketeer":"hit_musket", "stormcaller":"hit_bolt", "druid":"hit_thorn", "golem":"hit_golem"}

func _cue(base: String, n: int, at: Vector2, reach := HEAR_R, always := false, gain := 1.0) -> void:
	if audio == null or not audio.has_method("play"):
		return
	var d := 0.0 if always else _listener().distance_to(at)
	if d > reach:
		return
	var v := clampf(1.0 - (d - 6.0) / maxf(reach - 6.0, 1.0), 0.0, 1.0)
	var cue := base if n <= 1 else "%s%d" % [base, 1 + _snd_rng.randi() % n]
	audio.play(cue, false, v * gain)

func _unit_pos(id: Variant) -> Vector2:
	var u: Dictionary = sim.by_id.get(str(id), {})
	return u.pos if not u.is_empty() else Vector2.INF

func _gate_pos(gid: Variant) -> Vector2:
	for g in sim.gates:
		if str(g.id) == str(gid):
			return Sim.gate_front(g)
	return Vector2.INF

func _on_tower_broke(at: Vector3, stage: int) -> void:
	# 0.31.172: a tower breaking as it's hurt -- stone crumbling (louder when it falls)
	_cue("tm_crumble", 2, Vector2(at.x, at.z), 40.0, false, 0.65 if stage < 4 else 1.1)
	if stage >= 4:
		_cue("tm_rock_hit", 2, Vector2(at.x, at.z), 40.0, false, 1.0)

func _event_sound(e: Dictionary) -> void:
	if audio == null or not audio.has_method("play"):
		return
	var mine := str(e.get("id", "")) == str(hud.player_id)
	match str(e.get("k", "")):
		"attack":
			var src: Dictionary = sim.by_id.get(str(e.get("id", "")), {})
			if src.is_empty():
				return
			var ab := str(e.get("ability", ""))
			if ab == "hammer":
				_cue("hammerThrow", 1, src.pos, HEAR_R + 4.0, mine)
			elif str(e.get("kind", "")) == "ability" and str(sim.ability_of(src)) == "pierce":
				_cue("ab_pierce", 1, src.pos, HEAR_R + 4.0, mine)                # 0.31.171: the Sniper's PIERCE
			elif SHOT_CUE.has(str(src.get("shot", ""))):
				# 0.31.168: the Musketeer's flintlock, the Stormcaller's bolt, the Druid's thorn (0.31.171: their own)
				_cue(str(SHOT_CUE[str(src.shot)]), 1, src.pos, HEAR_R + (6.0 if str(src.shot) == "ball" else 0.0), mine)
			elif str(src.get("hid", "")) == "golem":
				_cue("atk_golem", 1, src.pos, HEAR_R, mine)                      # 0.31.171: his stone hammer
			elif src.cls == "ranger":
				_cue("tm_bow_shot", 2, src.pos, HEAR_R, mine)
			elif src.cls == "mage":
				if ab == "":
					_cue("tm_fireball", 3, src.pos, HEAR_R, mine)
			elif src.cls != "priest":
				_cue("tm_sword_swing", 3, src.pos, HEAR_R, mine)
		"hit":
			var at := _unit_pos(e.get("id", ""))
			if at == Vector2.INF:
				return
			var by: Dictionary = sim.by_id.get(str(e.get("by", "")), {})
			var hurt_me := mine or str(e.get("by", "")) == str(hud.player_id)
			if by.is_empty() or by.cls == "priest":
				return                                       # a drain is silent
			if HIT_CUE.has(str(by.get("hid", ""))):
				_cue(str(HIT_CUE[str(by.hid)]), 1, at, HEAR_R, hurt_me)          # 0.31.171: the new heroes' hits
			elif by.cls == "ranger":
				_cue("tm_bow_hit", 3, at, HEAR_R, hurt_me)
			elif by.cls == "mage":
				_cue("tm_spell_hit", 3, at, HEAR_R, hurt_me)
			else:
				_cue("tm_sword_hit", 3, at, HEAR_R, hurt_me)
		"blocked":
			_cue("tm_sword_block", 3, e.get("pos", _unit_pos(e.get("id", ""))), HEAR_R, mine)
		"nova":
			_cue("tm_firespray", 2, _unit_pos(e.get("id", "")), HEAR_R, mine)
		"whirl":
			_cue("ab_whirl", 1, _unit_pos(e.get("id", "")), HEAR_R, mine)       # 0.31.171: the Berserker's WHIRLWIND
		"block_up":
			_cue("ab_shield", 1, _unit_pos(e.get("id", "")), HEAR_R, mine)      # 0.31.171: the Knight's Q, the Crusader's W
		"gate_hit":
			_cue("tm_gate_hit", 2, _gate_pos(e.get("gate", "")), HEAR_R + 6.0)
		"tower_hit":
			# 0.31.177: a hero's hit on a tower thuds on its stone (yours always heard; the minions' left quiet)
			var tb: Dictionary = sim.by_id.get(str(e.get("by", "")), {})
			if bool(tb.get("hero", false)) and sim.moba != null and int(e.get("tw", -1)) >= 0 and int(e.tw) < sim.moba.towers.size():
				_cue("tm_gate_hit", 2, sim.moba.towers[int(e.tw)].p, HEAR_R, str(e.by) == str(hud.player_id), 0.8)
		"gate_broken":
			_cue("tm_crumble", 2, _gate_pos(e.get("gate", "")), 48.0)
			_announce_gate(e)
		"gate_rebuilt":
			_cue("tm_gate_close", 1, _gate_pos(e.get("gate", "")), 18.0)
		"gate_open":
			_cue("tm_gate_open", 1, _gate_pos(e.get("gate", "")), 12.0, false, 0.55)
		"kb":                                           # 0.31.180: the kill banners' sounds (siege_hud.gd kill_banner)
			var kind := str(e.get("kind", "kill"))
			var mine_kb := str(e.get("by", "")) == str(hud.player_id) or str(e.get("id", "")) == str(hud.player_id)
			match kind:
				"first_blood":
					_cue("kb_first_blood", 1, Vector2.ZERO, HEAR_R, true, 0.9)
					_herald_say("kb_first_blood")
				"multi":
					var mn := clampi(int(e.get("n", 2)), 2, 5)
					_cue(["", "", "kb_double", "kb_triple", "kb_quadra", "kb_penta"][mn], 1, Vector2.ZERO, HEAR_R, true,
						1.0 if mine_kb or mn >= 4 else 0.7)     # (a PENTAKILL is heard across the map, whoever's)
				"shutdown":
					_cue("kb_shutdown", 1, Vector2.ZERO, HEAR_R, true, 0.9)
					_herald_say("kb_shutdown")
				_:
					_cue("kb_kill", 1, Vector2.ZERO, HEAR_R, true, 0.8 if mine_kb else 0.5)
		"recall":                                       # 0.31.181: the recall's hum, and its arrival
			_cue("recall_start", 1, _unit_pos(e.get("id", "")), HEAR_R, mine, 0.8)
		"recall_done":
			_cue("recall_done", 1, (e.get("to", Vector2.ZERO) as Vector2), HEAR_R, mine, 0.9)
		"ace":
			_cue("kb_ace", 1, Vector2.ZERO, HEAR_R, true, 0.9)
			_herald_say("kb_ace")
		"multikill":                                    # 0.31.29: the Herald calls your multi-kills
			if str(e.get("id", "")) == hud.player_id and sim.by_id.has(hud.player_id):
				# (0.31.37: kept on my unit online too, where the sim's own count lives on the server -- a chest rule)
				sim.by_id[hud.player_id]["best_multi"] = maxi(int(sim.by_id[hud.player_id].get("best_multi", 0)), int(e.n))
			if str(e.get("id", "")) == hud.player_id:
				_herald_say("mk_" + ["", "", "double", "triple", "quadra", "penta", "legendary"][mini(int(e.n), 6)])
		"vanish":                                       # 0.31.32: the three upgrades' new abilities
			# (0.31.171: the Assassin's own; the Duelist's FEINT has its spell's)
			if str(sim.by_id.get(str(e.id), {}).get("hid", "")) != "duelist":
				_cue("ab_vanish", 1, _unit_pos(str(e.id)), 14.0, false, 0.8)
		"meteor_warn":
			_cue("tm_fireball", 3, e.pos, 40.0, false, 0.9)
		"meteor_hit":                                   # 0.31.58 (Kevin): quieter, less dramatic than Siege's bomb
			_cue("tm_fireball", 3, e.pos, 45.0, false, 0.55)
			_cue("tm_crumble", 2, e.pos, 32.0, false, 0.3)
		"pierce_hit":
			_cue("tm_bow_hit", 3, e.pos, HEAR_R, false, 1.1)
		"ult":                                          # 0.31.157 5V5: each ultimate its own sound
			# (0.31.171: all eighteen from tools/build_hero_sfx.py, "ult_<hero>")
			var hid := str(e.get("ult", ""))
			_cue("ult_" + hid if Moba.HEROES.has(hid) else "surge", 1, e.get("pos", _unit_pos(e.get("id", ""))), 40.0, mine)
		"flurry_hit":
			# 0.31.171: the Assassin's FLURRY slashes, the Duelist's GRAND CHALLENGE thrusts
			if str(sim.by_id.get(str(e.get("id", "")), {}).get("hid", "")) == "duelist":
				_cue("ab_thrust", 1, e.get("pos", Vector2.INF), HEAR_R, mine, 0.9)
			else:
				_cue("flurry", 3, e.get("pos", Vector2.INF), HEAR_R, mine)
		"lord_slam":
			_cue("tm_rock_hit", 2, e.get("pos", Vector2.INF), 40.0, false, 1.0)
		"lord_down", "camp_up", "lord_march", "wyrm_down":
			if str(e.k) != "camp_up" or str(e.get("kind", "")) in ["lord", "wyrm"]:
				_cue("horn", 1, Vector2.INF, 0.0, true, 0.8)
		"spell":                                               # 0.31.167: W and E, each its sound
			var sc: Array = SPELL_CUE.get(str(e.get("spell", "")), ["tm_spell_hit", 3, 0.8])
			_cue(str(sc[0]), int(sc[1]), e.get("pos", Vector2.INF), 30.0, mine, float(sc[2]))
		"slam":
			# a leap's landing (0.31.171: LEAP's and DRAGON DIVE's own)
			var land: String = {"barbarian":"ab_leap_land", "dragoon":"ult_dragoon_land"}.get(
				str(sim.by_id.get(str(e.get("id", "")), {}).get("hid", "")), "")
			if land != "":
				_cue(land, 1, e.get("pos", Vector2.INF), 30.0, mine)
			else:
				_cue("tm_rock_hit", 2, e.get("pos", Vector2.INF), 30.0, false, 0.9)
		"pillar":
			_cue("ab_pillar", 1, e.get("c", Vector2.INF), 30.0, false, 1.0)         # 0.31.171: the eruption
		"trap_snap":
			_cue("ab_trap_snap", 1, e.get("pos", Vector2.INF), 24.0, false, 1.0)
		"burst":                                               # 0.31.168: a powder keg, roots
			if str(e.get("spell", "")) == "keg":
				_cue("tm_bomb_blast", 1, e.get("c", Vector2.INF), 36.0, false, 0.8)
			else:
				_cue("ab_entangle", 1, e.get("c", Vector2.INF), 24.0, false, 1.0)  # 0.31.171: the roots
		"zap":                                                 # 0.31.168: a THUNDERSTORM bolt
			_cue("hit_bolt", 1, e.get("c", Vector2.INF), 36.0, false, 1.0)
		"riposte":
			_cue("ab_riposte", 1, e.get("pos", Vector2.INF), HEAR_R, mine, 1.0)    # 0.31.171: the answer
		"wyrm_breath":                                         # 0.31.166: the Grave Wyrm's soul-fire
			_cue("tm_fireball", 3, e.get("pos", Vector2.INF), 40.0, false, 1.0)
		"buff":
			_cue("surge", 1, _unit_pos(e.get("id", "")), 24.0, mine, 0.8)
		"ult_ready":
			if mine:
				_cue("levelUp", 1, Vector2.INF, 0.0, true, 0.8)
		"gold":
			if mine:
				_cue("coin", 1, Vector2.INF, 0.0, true, 0.45)
		"boom":
			_cue("tm_spell_hit", 3, e.get("pos", Vector2.INF), HEAR_R)
		"dodge":
			_cue("tm_jump_dirt", 1, _unit_pos(e.get("id", "")), 14.0, mine)
		"resurrect":
			_cue("tm_revive", 1, e.get("pos", Vector2.INF), HEAR_R, str(e.get("by", "")) == str(hud.player_id) or mine)
func _footsteps(delta: float) -> void:
	# Your own footsteps, by what you're walking on: water when wading, stone in the keeps and on the fords, earth
	# elsewhere. Knights (and Crusaders) clink in mail.
	if audio == null or not audio.has_method("play"):
		return
	var me: Dictionary = sim.by_id.get(str(hud.player_id), {})
	if me.is_empty() or not sim.alive(me):
		_step_last = Vector2.INF
		return
	var p: Vector2 = me.pos
	var moved := 0.0 if _step_last == Vector2.INF else p.distance_to(_step_last)
	_step_last = p
	if moved / maxf(delta, 0.001) < 1.2:
		_step_t = 0.12                                       # first step lands soon after you start moving
		return
	_step_t -= delta
	if _step_t > 0.0:
		return
	var speed := moved / maxf(delta, 0.001)
	_step_t = clampf(1.55 / maxf(speed, 1.0), 0.24, 0.42)
	var surf := "dirt"
	if Sim.water_depth(p) > 0.05:                # (0.31.165: the Rift's river is shallow -- 0.15 m at its deepest)
		surf = "water"
	elif Land.keep_dist(p) < Keep.R + 0.5 or Land.on_ford(p):
		surf = "stone"                        # (0.31.126: the paths are dirt now, so only the keeps and the fords sound of stone)
	var chain := "_chain" if me.cls == "knight" else ""
	audio.play("tm_step_%s%s%d" % [surf, chain, 1 + _snd_rng.randi() % 5], false, 1.0)

func _ambience(delta: float) -> void:
	# Forest birds under the whole match; the river louder as you near it.
	if _amb.is_empty():
		for k in ["forest_day", "river"]:
			var st = load("res://assets/sounds/ambience/%s.ogg" % k)
			if st == null:
				continue
			st.loop = true
			var pl := AudioStreamPlayer.new()
			pl.stream = st
			pl.volume_db = -80.0
			add_child(pl)
			pl.play(randf() * 50.0)
			_amb[k] = pl
	var muted: bool = audio == null or bool(audio.get("muted")) or not get_window().has_focus()
	var lv: Dictionary = audio.get("levels") if audio != null and audio.get("levels") != null else {"master":1.0, "combat":1.0}
	var base := 0.0 if muted else float(lv.get("master", 1.0)) * float(lv.get("combat", 1.0))
	var at := _listener()
	var want := {
		"forest_day": 0.22,
		# 0.30.9 (Kevin: "lower the volume of the river"): 0.55 -> 0.14 and the waterfall 0.7 -> 0.12. The river file
		# is ~5 dB hotter than the forest bed and the waterfall ~9 dB, so these now peak near the bed's level.
		"river": 0.14 * clampf(1.0 - Land.river_off(at) / 16.0, 0.0, 1.0),
	}
	for k in _amb:
		var pl: AudioStreamPlayer = _amb[k]
		var g := float(want.get(k, 0.0)) * base
		var cur := db_to_linear(pl.volume_db)
		pl.volume_db = linear_to_db(maxf(lerpf(cur, g, minf(1.0, delta * 3.0)), 0.00001))
	_music_step(delta, muted, lv)

func _music_step(delta: float, muted: bool, lv: Dictionary) -> void:
	if _music == null:
		if not ResourceLoader.exists(MUSIC_PATH):
			return
		var st = load(MUSIC_PATH)
		if st == null:
			return
		st.loop = true
		_music = AudioStreamPlayer.new()
		_music.stream = st
		_music.volume_db = -80.0
		add_child(_music)
		_music.play()
	var target := 0.0 if muted else MUSIC_GAIN * float(lv.get("master", 1.0)) * float(lv.get("music", 1.0))
	var cur := db_to_linear(_music.volume_db)
	_music.volume_db = linear_to_db(maxf(lerpf(cur, target, minf(1.0, delta * 2.0)), 0.00001))   # eases only on mute / slider


# The Herald's in-match lines (0.31.29): assets/vo/herald/<id>.ogg, at the master volume like the tutorial's voice,
# a newer line cutting off the one before (a quick triple steps on the double).
var _herald: AudioStreamPlayer = null
var _herald_until := 0.0                    # when the line playing ends (by its length: the playing flag can stick)
var _ann_clock := 0.0                       # frame time since the match opened (the announcer's clock)
const HERALD_GAIN := 0.5      # 0.31.58 (Kevin: lower the announcer): -6 dB, under the louder game sounds

func _herald_say(id: String) -> void:
	var path := "res://assets/vo/herald/%s.ogg" % id
	if not ResourceLoader.exists(path):
		return
	var master := 1.0
	var muted := false
	if audio != null:
		master = float(audio.levels.get("master", 1.0))
		muted = bool(audio.get("muted"))
	if muted or master <= 0.0:
		return
	if _herald == null:
		_herald = AudioStreamPlayer.new()
		_herald.bus = "Master"
		add_child(_herald)
	_herald.stop()
	_herald.stream = load(path)
	_herald.volume_db = linear_to_db(master * HERALD_GAIN)
	_herald.play()
	_herald_until = _ann_clock + _herald.stream.get_length()


# ---------- the Herald's match announcements (0.31.30, Kevin: "only important ones") ----------
# assets/vo/herald/an_<key>_<n>.ogg (n variants, picked at random). From your team's side. Priorities: 3 cuts in on
# anything (the end, the last minute, ten seconds); 2 waits for the line playing to finish; lower-priority calls that
# can't play within 5 s are dropped. Each key has a cooldown (gates break often). Multi-kill calls (priority 2) share
# the same voice. (0.31.169: Siege's King, jail and outpost calls went with it; a gate of a keep broken is called.)
const ANNOUNCE := {
	"start":[2, 0.0], "our_gate":[2, 45.0], "their_gate":[2, 45.0],
	"last_minute":[3, 0.0], "ten_seconds":[3, 0.0], "victory":[3, 0.0], "defeat":[3, 0.0], "draw":[3, 0.0]}
var _ann_last := {}
var _ann_queue: Array = []                  # [key, priority, wanted_at]
var _ann_flags := {}

func _announce(key: String) -> void:
	if not ANNOUNCE.has(key):
		return
	var now := _ann_clock
	var cd: float = ANNOUNCE[key][1]
	if cd > 0.0 and now - float(_ann_last.get(key, -999.0)) < cd:
		return
	_ann_last[key] = now
	var pri: int = ANNOUNCE[key][0]
	if pri >= 3:
		_ann_queue.clear()
		_herald_say(_ann_file(key))
	else:
		_ann_queue.append([key, pri, now])

func _ann_file(key: String) -> String:
	var n := 0
	while ResourceLoader.exists("res://assets/vo/herald/an_%s_%d.ogg" % [key, n + 1]):
		n += 1
	return "an_%s_%d" % [key, randi_range(1, maxi(n, 1))]

func _announce_tick() -> void:
	# the queue, and the clock-driven calls (start, last minute, ten seconds, the end)
	if sim == null or tutorial:
		return                              # (0.31.181: the tutorial's Herald does the talking)
	var now := _ann_clock
	if not _ann_queue.is_empty() and now >= _herald_until:
		var item: Array = _ann_queue.pop_front()
		if now - float(item[2]) <= 5.0:
			_herald_say(_ann_file(str(item[0])))
	if not _ann_flags.has("start") and sim.time > 1.0:
		_ann_flags["start"] = true
		_announce("start")
	var left: float = float(sim.match_time) - sim.time
	if not _ann_flags.has("minute") and left <= 60.0 and left > 55.0:
		_ann_flags["minute"] = true
		_announce("last_minute")
	if not _ann_flags.has("ten") and left <= 10.0 and left > 8.0 and not sim.ended:
		_ann_flags["ten"] = true
		_announce("ten_seconds")
	if not _ann_flags.has("end") and sim.ended:
		_ann_flags["end"] = true
		var me: Dictionary = sim.by_id.get(hud.player_id, {})
		var team: int = int(me.get("team", 0))
		_announce("draw" if int(sim.winner) < 0 else ("victory" if int(sim.winner) == team else "defeat"))

func _announce_gate(e: Dictionary) -> void:
	# a gate of a keep broken: "our gate" / "their gate", from your side
	var me: Dictionary = sim.by_id.get(hud.player_id, {}) if sim != null else {}
	var gi := int(e.get("gate", -1))
	if me.is_empty() or gi < 0 or gi >= sim.gates.size():
		return
	_announce("our_gate" if int(sim.gates[gi].team) == int(me.team) else "their_gate")


# ---------- quick chat (0.31.111, Kevin: "add the quick chat pings") ----------
var _qc_at := -100.0

func _on_quick_chat(i: int) -> void:
	if sim == null or i < 0 or i >= Net.QUICK_CHAT.size():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _qc_at < Net.QC_GAP:
		hud.toast("One quick chat every %d seconds" % int(Net.QC_GAP), Color("#c2cdea"))
		return
	_qc_at = now
	hud.add_ping(hud.player_id, i, player_name)            # shown at once; the server tells the others
	_ping_sound()
	if online:
		_net_send({"t":"qc", "i":i})

func _ping_sound() -> void:
	if audio != null and audio.has_method("play"):
		audio.play("ping")
