extends Control
# Offline Siege match: you plus bots. Owns the simulation, steps it at a fixed rate, and feeds the
# 3D view and HUD. Emits `exited` when the player leaves.
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Land = preload("res://scripts/siege/siege_land.gd")
const View = preload("res://scripts/siege/siege_view.gd")
const Hud = preload("res://scripts/siege/siege_hud.gd")
const Diag = preload("res://scripts/siege/siege_diag.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
const VisualTheme = preload("res://scripts/ui/visual_theme.gd")
const Lobby = preload("res://scripts/siege/lobby_panel.gd")

signal exited
# 0.31.73: the server refused our protocol. verdict "update" (server newer: this build is too old -> the app shows
# the blocking Update screen) or "server_old" (server older: "Servers are updating"). See Net.version_verdict.
signal version_mismatch(server_v: int, verdict: String)

var team_size := 16
var tutorial := false          # the Herald's walkthrough (scripts/siege/tutorial.gd)
var tut: Control = null
const Tutorial = preload("res://scripts/siege/tutorial.gd")
const TUTORIAL_GOLD := 250
# 3D resolution as a fraction of the PHYSICAL screen (window pixels, not logical UI units).
var render_scale := 1.0
const FPS_CAP := 30         # hard-locked (Round 32, Kevin: no fps options) -- the sim ticks at 30 Hz anyway
var _prev_max_fps := 0
var fps_cap := FPS_CAP
# Thermal guard: field logs (S21 Ultra) show fps sliding for several seconds before a GPU hang.
# If fps stays under GUARD_FPS for GUARD_SECONDS while capped at 60, drop to 30 automatically.
const GUARD_FPS := 50
const GUARD_SECONDS := 3
var _guard_low := 0
var _guard_clock := 0.0
var guard_tripped := false
var _guard_res_low := 0
var low_fx := false
var hq_gfx := true          # High-quality graphics (Settings): shadows, glow, smoother edges
var audio: Node = null
var profile = null       # scripts/meta/profile.gd — rewards, challenges and cosmetics
var rewards: Dictionary = {}
var match_result: Dictionary = {}
var _lifts := 0          # times the player joined a lift of their own Oracle this match

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
			# The server starts the next match on its own; just clear the results screen.
			if hud.result_panel != null:
				hud.result_panel.queue_free()
				hud.result_panel = null
			hud.toast("Next match starts shortly...", Color("#f2d18d"))
		else:
			_restart())
	hud.res_label_source = func() -> float: return render_scale
	hud.res_cycled.connect(func():
		var steps := [1.0, 0.75, 0.5]
		var i := 0
		for j in steps.size():
			if absf(steps[j] - render_scale) < 0.01: i = j
		set_render_scale(steps[(i + 1) % steps.size()]))
	hud.workshop_tools.connect(func(): _act("take_tools"))
	hud.workshop_buy.connect(func(id): _act("buy", id))
	hud.workshop_leave.connect(func(): _act("workshop_leave"))
	hud.action_pressed.connect(_on_action)
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
		if tutorial:
			team_size = 2                      # a quiet castle: one ally, two enemies (one becomes the dummy)
		sim.setup(team_size, int(Time.get_unix_time_from_system()) & 0x7fffffff)
		ready_times["sim.setup"] = Time.get_ticks_msec() - t_sim
		view = View.new()
		view.low_fx = low_fx
		view.hq_gfx = hq_gfx
		view.player_looks = _looks()
		viewport.add_child(view)
		_view_steps = view.setup_steps(sim))
	# (the view's own steps run from _view_steps between these two: the array is filled by the first step)
	steps.append(_run_view_steps)
	steps.append(func():
		hud.sim = sim
		_accum = 0.0
		_result_shown = false
		if tutorial:
			tut = Tutorial.new()
			add_child(tut)                     # after the HUD: drawn on top of it
			tut.begin(self)
		_lifts = 0)
	return steps

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

func _looks() -> Dictionary:
	var out := {}
	if profile != null:
		for cls in ["knight", "barbarian", "rogue", "ranger", "mage", "worker", "crusader", "berserker", "necromancer", "assassin", "sniper", "archmage"]:
			var l: Dictionary = profile.look_for(cls)
			if not l.is_empty():
				out[cls] = l
	return out

func _count(e: Dictionary) -> void:
	if str(e.get("k", "")) == "lift_join" and str(e.get("id", "")) == hud.player_id and sim != null \
			and sim.by_id.has(hud.player_id) and int(e.get("team", -1)) == int(sim.by_id[hud.player_id].team):
		_lifts += 1

func _start_online() -> void:
	ws = WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 20
	ws.outbound_buffer_size = 1 << 16
	var err := ws.connect_to_url(net_url)
	net_state = "connecting"
	_net_started = Time.get_ticks_msec() / 1000.0
	diag.write("NET connect %s err=%d" % [net_url, err])
	hud.toast("Connecting to the Siege server...", Color("#f2d18d"))
	lobby = Lobby.new()
	lobby.audio = audio
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

func _build_online_match(msg: Dictionary) -> void:
	# A new match (or the first one): rebuild the mirror sim and the 3D view.
	if is_instance_valid(view):
		view.queue_free()
	if hud.result_panel != null:
		hud.result_panel.queue_free()
		hud.result_panel = null
	sim = Sim.new()
	sim.setup(int(msg.get("team_size", Net.TEAM_SIZE)), int(msg.get("seed", 1)), -1)
	var me_id := str(msg.get("you", ""))
	hud.player_id = me_id
	view = View.new()
	view.low_fx = low_fx
	view.hq_gfx = hq_gfx
	view.player_id = me_id
	view.player_looks = _looks()
	viewport.add_child(view)
	view.setup(sim)
	hud.sim = sim
	net_match = int(msg.get("match", 0))
	_result_shown = false
	_lifts = 0
	net_state = "playing"
	diag.write("NET welcome match=%d you=%s players=%d" % [net_match, me_id, int(msg.get("players", 1))])
	hud.toast("Online: %d player%s" % [int(msg.get("players", 1)), "" if int(msg.get("players", 1)) == 1 else "s"], VisualTheme.GOLD)
	if is_instance_valid(lobby):
		_cover_show()                      # the card straight over the lobby (the warm-up keeps it up; tests drop it)
		lobby.queue_free()
		lobby = null

func _net_process(delta: float) -> void:
	if ws == null:
		return
	ws.poll()
	var st := ws.get_ready_state()
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
		_net_fail("Disconnected from the server" if sim != null else "Could not connect to the server")
		return
	if net_state == "connecting":
		net_state = "waiting"
		_net_send({"t":"hello", "v":Net.VERSION, "name":player_name, "build":Diag.BUILD, "pred":true})
	while ws.get_available_packet_count() > 0:
		var msg := Net.decode(ws.get_packet())
		match str(msg.get("t", "")):
			"welcome":
				if int(msg.get("match", -1)) != net_match:
					_build_online_match(msg)
			"s":
				if sim == null:
					continue
				Net.apply(sim, msg, hud.player_id, true)
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
				lobby_msgs += 1
				if lobby_msgs == 1:
					diag.write("NET lobby left=%.1f names=%d online=%d running=%s" % [float(msg.get("left", 0)), (msg.get("names", []) as Array).size(), int(msg.get("online", 0)), str(msg.get("running", false))])
				if sim == null and is_instance_valid(lobby):
					lobby.update(msg)
			"m":                                              # 0.31.23: my task, sent on its own when it changes
				if sim != null and sim.by_id.has(hud.player_id):
					sim.by_id[hud.player_id].task = msg.get("task", {})
			"bye":
				_net_bye = msg
				if _net_version_refused(-1, ""):
					return
				var why := str(msg.get("why", ""))
				_net_fail({"full":"Server is full"}.get(why, "Server closed the connection"))
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
		Net.interpolate_at(sim, _net_rt, hud.player_id)
	# Inputs: movement and held attack at 20 Hz (or when they change); actions go immediately.
	_send_clock += delta
	var mv: Vector2 = hud.move_vector() if not hud.paused() else Vector2.ZERO
	var hold: bool = hud.attack_held() and not hud.paused()
	var bhold: bool = hud.ability_held() and not hud.paused()
	# Client-side prediction: move our own unit now (same movement code as the server); the server
	# validates the position we send. Snapshots only correct us when we've drifted > 2.5 m.
	var me_p: Dictionary = sim.by_id.get(hud.player_id, {})
	if not me_p.is_empty() and sim.client_drivable(me_p):
		sim.predict_step(me_p, mv, delta)
		# Held ATTACK: the server swings every time it can; start the same swings locally.
		if hold and me_p.cls != "priest" and sim.can_act(me_p) and not me_p.carrying:
			sim._start_attack(me_p, "attack")
		sim.drain_events()                         # (prediction events are shown in _act; nothing else should pile up)
	if _send_clock >= 0.05 or (mv - _sent_move).length() > 0.25 or hold != _sent_hold or bhold != _sent_bhold:
		_send_clock = 0.0
		_sent_move = mv
		_sent_hold = hold
		_sent_bhold = bhold
		var msg_in := {"t":"in", "m":mv, "h":hold, "b":bhold}
		if not me_p.is_empty():
			msg_in["p"] = me_p.pos
			msg_in["f"] = me_p.face
		_net_send(msg_in)

func _restart() -> void:
	if is_instance_valid(view):
		view.queue_free()
	if hud.result_panel != null:
		hud.result_panel.queue_free()
		hud.result_panel = null
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
		elif action == "ability" and not me_a.is_empty() and sim.client_drivable(me_a):
			# 0.31.23 (Kevin: "abilities lag"): the ability's start shows now -- the swing, the spin, the ring; the
			# server resolves what it does (the predicted start happens in _process right after this frame's input)
			if sim.predict_ability(me_a):
				for e in sim.drain_events():
					_pred_fx[str(e.k)] = Time.get_ticks_msec() / 1000.0
					view.on_event(e)
					_event_sound(e)
		var msg_a := {"t":"in", "m":hud.move_vector(), "h":hud.attack_held(), "b":hud.ability_held(), "k":hud.block_held(), "a":action, "arg":arg}
		if not me_a.is_empty():
			msg_a["p"] = me_a.pos
			msg_a["f"] = me_a.face
		_net_send(msg_a)
		return
	sim.act(hud.player_id, action, arg)

func _on_action(kind: String) -> void:
	match kind:
		"attack": _act("attack")
		"ability": _act("ability")
		"dodge": _act("dodge")
		"action": _act("interact")

# ---- Warm-up cover (Round 16, Kevin: the 3D world showed black for a few seconds at match start: the
# phone compiling the scene's shader pipelines). A FATEBOUND card covers the first moments while the
# camera visits the key places so their materials compile behind it; it lifts once the engine's
# pipeline-compilation counters have been still for WARM_STILL (never before WARM_MIN, at most
# WARM_MAX). Offline the match clock waits. Skipped under scripted main loops (tests, render tools).
const WARM_MIN := 0.6
const WARM_MAX := 10.0
const WARM_STILL := 0.5
const _LOGO_FONT = preload("res://assets/fonts/LuckiestGuy-Regular.ttf")
var _warm: Dictionary = {}
var _warm_done := false
var _cover: ColorRect = null
var _cover_sub: Label = null
var _cover_t := 0.0

func _cover_show() -> void:
	# The FATEBOUND card over everything (the staged start builds the world behind it; the warm-up keeps it up).
	if _cover != null:
		return
	var cover := ColorRect.new()
	cover.color = Color("#120c07")
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	cover.z_index = 100
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	cover.add_child(box)
	var title := Label.new()
	title.text = "FATEBOUND"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", _LOGO_FONT)
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color("#ffd257"))
	title.add_theme_color_override("font_outline_color", Color("#2e1908"))
	title.add_theme_constant_override("outline_size", 12)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Preparing the battlefield"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_override("font", VisualTheme.BOLD_FONT)
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color("#f0e4c8"))
	box.add_child(sub)
	add_child(cover)
	_cover = cover
	_cover_sub = sub

func _cover_tick(delta: float) -> void:
	_cover_t += delta
	if _cover_sub != null:
		_cover_sub.text = "Preparing the battlefield" + ".".repeat(1 + int(_cover_t * 3.0) % 3)

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
		for q in [Vector2(0.0, 6.0), Vector2(0.0, 20.0), Vector2(0.0, 27.0), Vector2(-26.5, 14.0), Vector2(0.0, -6.0)]:
			spots.append(Sim._c(t, q))
	spots.append(Vector2.ZERO)
	for op in sim.outposts:
		spots.append(op.p)
	_warm = {"cover": _cover, "t": 0.0, "last": -1, "still": 0.0, "spots": spots, "i": 0, "fade": -1.0}

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
	var cover: ColorRect = w.cover
	if float(w.fade) < 0.0:
		if (int(w.i) > spots.size() * 2 and float(w.t) >= WARM_MIN and float(w.still) >= WARM_STILL) or float(w.t) >= WARM_MAX:
			w.fade = 0.0
			diag.mark("warm-up %.1f s, %d pipeline compiles" % [float(w.t), c])
		return true
	w.fade = float(w.fade) + delta
	cover.modulate.a = clampf(1.0 - float(w.fade) / 0.3, 0.0, 1.0)
	if float(w.fade) >= 0.3:
		cover.queue_free()
		_cover = null
		_cover_sub = null
		_warm = {}
		return false
	return float(w.fade) < 0.15

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
	_ambience(delta)
	var t_start := Time.get_ticks_usec()
	if online:
		pass   # the server steps the match; _net_process applied the latest snapshot
	elif not hud.paused() or sim.ended:
		sim.set_move(hud.player_id, hud.move_vector())
		var me_b: Dictionary = sim.by_id.get(hud.player_id, {})
		if hud.ability_held() and not me_b.is_empty() and sim.ability_of(me_b) == "block":
			sim.act(hud.player_id, "ability")
		if hud.block_held() and not me_b.is_empty():
			sim.act(hud.player_id, "block")
		if hud.attack_held():
			var me: Dictionary = sim.by_id[hud.player_id]
			if sim.can_act(me) and not me.carrying:
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
	diag.mark("view.sync")
	view.proj_lead = 0.0 if online else _accum          # online, projectiles interpolate (Net)
	var t_view := Time.get_ticks_usec()
	view.sync(delta)
	diag.add_time("view", Time.get_ticks_usec() - t_view)
	diag.mark("process done")
	_thermal_guard(delta)
	diag.add_time("game", Time.get_ticks_usec() - t_start)
	if sim.ended and not _result_shown:
		_result_shown = true
		diag.write("MATCH END winner=%d reason=%s score=%s" % [sim.winner, sim.end_reason, str(sim.score)])
		var me: Dictionary = (sim.by_id[hud.player_id] as Dictionary).duplicate()
		me["lifts"] = _lifts
		var won: bool = sim.winner == int(me.team)
		var draw: bool = sim.winner == -1
		match_result = {}
		if profile != null and not tutorial:      # a tutorial is not a match: no rewards/challenges
			match_result = profile.apply_match(me, won, draw, online)
			rewards = match_result.rewards
		diag.write("REWARDS %s" % str(match_result.get("rewards", {}).get("gold", 0)))
		hud.show_result(match_result)

func finish_tutorial() -> void:
	# The Herald's last line: mark it done, pay the recruit, back to the menu.
	if profile != null:
		if not bool(profile.d.get("tutorial_done", false)):
			profile.d.gold = int(profile.d.gold) + TUTORIAL_GOLD
		profile.d["tutorial_done"] = true
		profile.save()
	exited.emit()

func _thermal_guard(delta: float) -> void:
	_guard_clock += delta
	if _guard_clock < 1.0:
		return
	_guard_clock = 0.0
	if hud.paused():
		_guard_low = 0
		return
	# Locked at 30 fps (Round 32): what's left of the guard is the resolution step when even 30 can't be held.
	_thermal_guard_res()

func _thermal_guard_res() -> void:
	# Second step: already at 30 fps and still missing frames -> drop 3D resolution to 75 %.
	if fps_cap == 30 and render_scale > 0.8 and Engine.get_frames_per_second() < 26:
		_guard_res_low += 1
		if _guard_res_low >= 5:
			diag.write("THERMAL GUARD still under 26 fps at 30 cap -> 3D resolution 75%")
			guard_tripped = true
			set_render_scale(0.75)
			hud.toast("Device running hot: resolution 75%", Color("#f2d18d"))
	else:
		_guard_res_low = 0

func set_fps_cap(v: int) -> void:
	fps_cap = v
	Engine.max_fps = v
	if diag != null:
		diag.write("FPS CAP %d" % v)

func _exit_tree() -> void:
	Engine.max_fps = _prev_max_fps
	if ws != null:
		ws.close(1000, "leave")

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
				return                                       # catapult stones have their own crash; a drain is silent
			if by.cls == "ranger":
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
			_cue("tm_sword_swing", 3, _unit_pos(e.get("id", "")), HEAR_R, mine)
		"gather":
			_cue("tm_chop" if str(e.get("kind", "")) == "wood" else "tm_mine", 4 if str(e.get("kind", "")) == "wood" else 5,
				_unit_pos(e.get("id", "")), 18.0, mine)
		"repair":
			_cue("tm_mine", 5, _unit_pos(e.get("id", "")), 18.0, mine)
		"deliver":
			_cue("tm_chest_close", 2, _unit_pos(e.get("id", "")), 16.0, mine)
		"upgrade", "hat_upgrade":
			_cue("tm_chest_open", 2, _unit_pos(e.get("id", "")), 16.0, mine or str(e.get("id", "")) == "")
		"hat_take", "hat_pick":
			_cue("tm_unsheath", 2, _unit_pos(e.get("id", "")), 14.0, mine)
		"hat_drop":
			_cue("tm_sheath", 2, e.get("pos", Vector2.INF), 14.0)
		"gate_hit":
			_cue("tm_gate_hit", 2, _gate_pos(e.get("gate", "")), HEAR_R + 6.0)
		"bomb_boom":                                    # 0.31.58 (Kevin): a huge bang that rolls off into a long rumble
			_cue("tm_bomb_blast", 1, e.pos, 95.0, false, 2.6)
		"bomb_throw":
			_cue("tm_firespray", 2, e.from, HEAR_R, false, 0.8)      # the fuse catching
		"bomb_pick", "bomb_spawn":
			_cue("tm_gate_close", 1, e.get("pos", _listener()) if e.k == "bomb_spawn" else _unit_pos(str(e.id)), 14.0, false, 0.5)
		"gate_broken":
			_cue("tm_crumble", 2, _gate_pos(e.get("gate", "")), 48.0)
		"gate_rebuilt":
			_cue("tm_gate_close", 1, _gate_pos(e.get("gate", "")), 18.0)
		"gate_close":                                        # allies pass through every few seconds: keep it soft
			_cue("tm_gate_close", 1, _gate_pos(e.get("gate", "")), 12.0, false, 0.55)
		"gate_open":
			_cue("tm_gate_open", 1, _gate_pos(e.get("gate", "")), 12.0, false, 0.55)
		"jail_reset":
			_cue("tm_unlock", 1, _gate_pos(e.get("gate", "")), 18.0)
		"pickup", "drop", "rescue", "gate_broken", "outpost_captured", "outpost_lost":
			_announce_event(e)
		"multikill":                                    # 0.31.29: the Herald calls your multi-kills
			if str(e.get("id", "")) == hud.player_id and sim.by_id.has(hud.player_id):
				# (0.31.37: kept on my unit online too, where the sim's own count lives on the server -- a chest rule)
				sim.by_id[hud.player_id]["best_multi"] = maxi(int(sim.by_id[hud.player_id].get("best_multi", 0)), int(e.n))
			if str(e.get("id", "")) == hud.player_id:
				_herald_say("mk_" + ["", "", "double", "triple", "quadra", "penta", "legendary"][mini(int(e.n), 6)])
		"vanish":                                       # 0.31.32: the three upgrades' new abilities
			_cue("tm_firespray", 2, _unit_pos(str(e.id)), 14.0, false, 0.35)
		"meteor_warn":
			_cue("tm_fireball", 3, e.pos, 40.0, false, 0.9)
		"meteor_hit":                                   # 0.31.58 (Kevin): quieter, less dramatic than the bomb
			_cue("tm_fireball", 3, e.pos, 45.0, false, 0.55)
			_cue("tm_crumble", 2, e.pos, 32.0, false, 0.3)
		"pierce_hit":
			_cue("tm_bow_hit", 3, e.pos, HEAR_R, false, 1.1)
		"launch_count":                                 # 0.31.28: the launcher's lever
			_cue("tm_gate_close", 1, e.pos, 30.0, false, 0.8)
		"launch":
			_cue("tm_rock_throw", 2, e.pos, 60.0, false, 1.5)
			_cue("tm_crumble", 2, e.pos, 40.0, false, 0.5)
		"land":
			_cue("tm_rock_hit", 2, e.pos, 30.0, false, 0.9)
		"catapult_fire":
			_cue("tm_rock_throw", 2, e.get("from", Vector2.INF), 32.0)
		"catapult_hit":
			_cue("tm_rock_hit", 2, e.get("pos", Vector2.INF), 36.0)
		"boom":
			_cue("tm_spell_hit", 3, e.get("pos", Vector2.INF), HEAR_R)
		"ladder_up", "tower_up":
			_cue("tm_land_wood", 1, _unit_pos(e.get("id", "")), 16.0, mine)
		"tower_down":
			_cue("tm_land_dirt", 1, _unit_pos(e.get("id", "")), 16.0, mine)
		"dodge":
			_cue("tm_jump_dirt", 1, _unit_pos(e.get("id", "")), 14.0, mine)
		"fish_cast":
			_cue("tm_splash", 1, e.get("pos", Vector2.INF), 16.0, mine)
		"fish_caught":
			_cue("tm_water_jump", 1, e.get("pos", Vector2.INF), 16.0, mine)
		"node_fell":                                          # 0.31.0: a tree comes down / a boulder breaks
			if str(e.get("kind", "")) == "wood":
				_cue("tm_land_wood", 1, e.get("pos", Vector2.INF), 26.0, false, 1.0)
			else:
				_cue("tm_crumble", 2, e.get("pos", Vector2.INF), 26.0)
		"resurrect":
			_cue("tm_revive", 1, e.get("pos", Vector2.INF), HEAR_R, str(e.get("by", "")) == str(hud.player_id) or mine)
		"item_pickup":
			_cue("tm_land_wood" if str(e.get("kind", "")) == "log" else "tm_mine", 1 if str(e.get("kind", "")) == "log" else 5,
				_unit_pos(e.get("id", "")), 14.0, mine, 0.8)

func _footsteps(delta: float) -> void:
	# Your own footsteps, by what you're walking on: water when wading, wood on bridges, tower decks and ladders,
	# stone in the castles and on the brick paths, earth elsewhere. Knights (and Crusaders) clink in mail.
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
	if Sim.water_depth(p) > 0.15:
		surf = "water"
	elif int(me.get("tower", -1)) >= 0 or Land.on_bridge(p, 0.2):
		surf = "wood"
	elif (absf(p.x) <= Sim.CASTLE_HX + 1.0 and absf(p.y) >= Sim.CASTLE_SHIFT + Sim.FRONT_Z - 0.5) or Land.dist_to_paths(p) < Land.PATH_HALF_W:
		surf = "stone"
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
	var lv: Dictionary = audio.get("levels") if audio != null and audio.get("levels") != null else {"master":0.75, "combat":0.8}
	var base := 0.0 if muted else float(lv.get("master", 0.75)) * float(lv.get("combat", 0.8))
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
	var target := 0.0 if muted else MUSIC_GAIN * float(lv.get("master", 0.75)) * float(lv.get("music", 0.6))
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
		master = float(audio.levels.get("master", 0.8))
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
# anything (rescues, match point, the end, ten seconds); 2 waits for the line playing to finish; lower-priority calls
# that can't play within 5 s are dropped. Each key has a cooldown (gates break often). Multi-kill calls (priority 2)
# share the same voice.
const ANNOUNCE := {
	"start":[2, 0.0], "our_pickup":[2, 25.0], "their_pickup":[2, 25.0], "our_drop":[2, 20.0],
	"our_rescue":[3, 0.0], "their_rescue":[3, 0.0], "our_gate":[2, 45.0], "their_gate":[2, 45.0],
	"their_jail":[2, 45.0], "our_jail":[2, 45.0], "match_point_us":[3, 0.0], "match_point_them":[3, 0.0],
	"last_minute":[3, 0.0], "ten_seconds":[3, 0.0], "victory":[3, 0.0], "defeat":[3, 0.0], "draw":[3, 0.0],
	"our_outpost":[2, 20.0], "their_outpost":[2, 20.0]}          # 0.31.31: towers taken
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
		return
	var now := _ann_clock
	if not _ann_queue.is_empty() and now >= _herald_until:
		var item: Array = _ann_queue.pop_front()
		if now - float(item[2]) <= 5.0:
			_herald_say(_ann_file(str(item[0])))
	if not _ann_flags.has("start") and sim.time > 1.0:
		_ann_flags["start"] = true
		_announce("start")
	var left: float = Sim.MATCH_TIME - sim.time
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

func _announce_event(e: Dictionary) -> void:
	if sim == null or tutorial:
		return
	var me: Dictionary = sim.by_id.get(hud.player_id, {})
	if me.is_empty():
		return
	var mine: int = int(me.team)
	match str(e.k):
		"pickup":
			if int(e.team) == mine and int(e.get("carry_team", -1)) == mine:
				_announce("our_pickup")
			elif int(e.team) != mine and int(e.get("carry_team", -1)) != mine:
				_announce("their_pickup")
		"drop":
			var carrier: Dictionary = sim.by_id.get(str(e.get("id", "")), {})
			if int(e.team) == mine and not carrier.is_empty() and int(carrier.team) == mine:
				_announce("our_drop")
		"rescue":
			if int(e.team) == mine:
				_announce("our_rescue")
			else:
				_announce("their_rescue")
			if not sim.ended:
				if int(sim.score[mine]) == Sim.WIN_RESCUES - 1:
					_ann_queue.append(["match_point_us", 2, _ann_clock])
				elif int(sim.score[1 - mine]) == Sim.WIN_RESCUES - 1:
					_ann_queue.append(["match_point_them", 2, _ann_clock])
		"outpost_captured":
			_announce("our_outpost" if int(e.team) == mine else "their_outpost")
		"outpost_lost":
			if int(e.team) == mine:
				_announce("their_outpost")             # one of ours fell to them
		"gate_broken":
			var g: Dictionary = sim.gates[int(e.gate)] if int(e.gate) < sim.gates.size() else {}
			if g.is_empty():
				return
			var jail: bool = str(g.get("kind", "")) == "jail"
			if int(g.team) == mine:
				_announce("our_jail" if jail else "our_gate")
			else:
				_announce("their_jail" if jail else "their_gate")
