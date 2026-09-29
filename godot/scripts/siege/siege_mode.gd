extends Control
# Offline Siege match: you plus bots. Owns the simulation, steps it at a fixed rate, and feeds the
# 3D view and HUD. Emits `exited` when the player leaves.
const Sim = preload("res://scripts/siege/siege_sim.gd")
const View = preload("res://scripts/siege/siege_view.gd")
const Hud = preload("res://scripts/siege/siege_hud.gd")
const Diag = preload("res://scripts/siege/siege_diag.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
const VisualTheme = preload("res://scripts/ui/visual_theme.gd")

signal exited

var team_size := 16
# 3D resolution as a fraction of the PHYSICAL screen (window pixels, not logical UI units).
var render_scale := 1.0
const FPS_CAP := 60
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
var _net_started := 0.0
var _snap_t := 0.0
var _snap_dt := 1.0 / Net.SNAP_HZ
var _send_clock := 0.0
var _sent_move := Vector2(INF, INF)
var _sent_hold := false

var sim
var view
var hud
var viewport: SubViewport
var diag
var _accum := 0.0
var _result_shown := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	diag = Diag.new()
	diag.mode = self
	add_child(diag)
	# Cap Siege's frame rate: uncapped on a 120 Hz phone it ran flat out and thermal-throttled
	# within ~70 s (field log, S21 Ultra). Restored when leaving.
	_prev_max_fps = Engine.max_fps
	set_fps_cap(FPS_CAP)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
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
	hud = Hud.new()
	hud.diag = diag
	add_child(hud)
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
	hud.fps_toggled.connect(func(): set_fps_cap(30 if fps_cap == 60 else 60))
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
	if online:
		_start_online()
	else:
		_start()
	_resize_viewport()

func _start() -> void:
	sim = Sim.new()
	sim.setup(team_size, int(Time.get_unix_time_from_system()) & 0x7fffffff)
	view = View.new()
	view.low_fx = low_fx
	view.player_looks = _looks()
	viewport.add_child(view)
	view.setup(sim)
	hud.sim = sim
	_accum = 0.0
	_result_shown = false
	_lifts = 0

func _looks() -> Dictionary:
	var out := {}
	if profile != null:
		for cls in ["knight", "barbarian", "rogue", "ranger", "mage", "worker"]:
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
	if err != OK:
		_net_fail("Could not reach the server")

func _net_fail(why: String) -> void:
	if net_state == "closed":
		return
	net_state = "closed"
	diag.write("NET closed: " + why)
	hud.toast(why, VisualTheme.RED)
	if sim == null:
		# Nothing to show: go back home after the message is readable.
		get_tree().create_timer(2.5).timeout.connect(func(): exited.emit())

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
		if net_state != "closed":
			_net_fail("Disconnected from the server" if sim != null else "Could not connect to the server")
		return
	if net_state == "connecting":
		net_state = "waiting"
		_net_send({"t":"hello", "v":Net.VERSION, "name":player_name, "build":Diag.BUILD})
	while ws.get_available_packet_count() > 0:
		var msg := Net.decode(ws.get_packet())
		match str(msg.get("t", "")):
			"welcome":
				if int(msg.get("match", -1)) != net_match:
					_build_online_match(msg)
			"s":
				if sim == null:
					continue
				Net.apply(sim, msg, hud.player_id)
				_snap_dt = lerpf(_snap_dt, maxf(0.03, _snap_t), 0.2) if _snap_t > 0.0 else _snap_dt
				_snap_t = 0.0
				for e in msg.get("e", []):
					diag.event()
					_count(e)
					view.on_event(e)
					hud.on_event(e)
			"bye":
				var why := str(msg.get("why", ""))
				_net_fail({"full":"Server is full", "version":"Update the game to play online"}.get(why, "Server closed the connection"))
	if sim == null:
		return
	_snap_t += delta
	Net.interpolate(sim, _snap_t / maxf(0.03, _snap_dt))
	# Inputs: movement and held attack at 20 Hz (or when they change); actions go immediately.
	_send_clock += delta
	var mv: Vector2 = hud.move_vector() if not hud.pause_panel.visible else Vector2.ZERO
	var hold: bool = hud.attack_held() and not hud.pause_panel.visible
	if _send_clock >= 0.05 or (mv - _sent_move).length() > 0.25 or hold != _sent_hold:
		_send_clock = 0.0
		_sent_move = mv
		_sent_hold = hold
		_net_send({"t":"in", "m":mv, "h":hold})

func _restart() -> void:
	if is_instance_valid(view):
		view.queue_free()
	if hud.result_panel != null:
		hud.result_panel.queue_free()
		hud.result_panel = null
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
		_net_send({"t":"in", "m":hud.move_vector(), "h":hud.attack_held(), "a":action, "arg":arg})
		return
	sim.act(hud.player_id, action, arg)

func _on_action(kind: String) -> void:
	match kind:
		"attack": _act("attack")
		"ability": _act("ability")
		"dodge": _act("dodge")
		"action": _act("interact")

func _process(delta: float) -> void:
	if online:
		_net_process(delta)
	if sim == null:
		return
	diag.mark("input")
	var t_start := Time.get_ticks_usec()
	if online:
		pass   # the server steps the match; _net_process applied the latest snapshot
	elif not hud.pause_panel.visible or sim.ended:
		sim.set_move(hud.player_id, hud.move_vector())
		if hud.attack_held():
			var me: Dictionary = sim.by_id[hud.player_id]
			if sim.can_act(me) and not me.carrying:
				sim.act(hud.player_id, "attack")
		_accum += minf(delta, 0.1)
		diag.mark("sim.step")
		while _accum >= Sim.TICK:
			_accum -= Sim.TICK
			sim.step(Sim.TICK)
		for e in sim.drain_events():
			diag.mark("event " + str(e.k))
			diag.event()
			_count(e)
			view.on_event(e)
			hud.on_event(e)
	diag.mark("view.sync")
	view.sync(delta)
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
		if profile != null:
			match_result = profile.apply_match(me, won, draw, online)
			rewards = match_result.rewards
		diag.write("REWARDS %s" % str(match_result.get("rewards", {}).get("gold", 0)))
		hud.show_result(match_result)

func _thermal_guard(delta: float) -> void:
	_guard_clock += delta
	if _guard_clock < 1.0:
		return
	_guard_clock = 0.0
	if hud.pause_panel.visible:
		_guard_low = 0
		return
	if fps_cap != 60:
		_thermal_guard_res()
		return
	_guard_low = _guard_low + 1 if Engine.get_frames_per_second() < GUARD_FPS else 0
	if _guard_low >= GUARD_SECONDS:
		_guard_low = 0
		guard_tripped = true
		diag.write("THERMAL GUARD fps under %d for %ds -> 30 fps" % [GUARD_FPS, GUARD_SECONDS])
		set_fps_cap(30)
		hud.toast("Device running hot: 30 FPS mode on", Color("#f2d18d"))

func _thermal_guard_res() -> void:
	# Second step: already at 30 fps and still missing frames -> drop 3D resolution to 75 %.
	if fps_cap == 30 and render_scale > 0.8 and Engine.get_frames_per_second() < 26:
		_guard_res_low += 1
		if _guard_res_low >= 5:
			diag.write("THERMAL GUARD still under 26 fps at 30 cap -> 3D resolution 75%")
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
	if hud.result_panel != null:
		exited.emit()
	else:
		hud.pause_panel.visible = true
		hud._center(hud.pause_panel)
