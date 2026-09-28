extends Control
# Offline Siege match: you plus bots. Owns the simulation, steps it at a fixed rate, and feeds the
# 3D view and HUD. Emits `exited` when the player leaves.
const Sim = preload("res://scripts/siege/siege_sim.gd")
const View = preload("res://scripts/siege/siege_view.gd")
const Hud = preload("res://scripts/siege/siege_hud.gd")
const Diag = preload("res://scripts/siege/siege_diag.gd")

signal exited

var team_size := 6
const RENDER_SCALE := 0.8
# 3D is never rendered wider than this many pixels; at this zoom more is invisible but costs heat.
const MAX_3D_WIDTH := 720.0
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
var low_fx := false
var audio: Node = null

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
	# Same 3D viewport settings as the dice battle (battlefield.gd), which runs full matches on the
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
	hud.replay_requested.connect(_restart)
	hud.forge_roll.connect(func(held): _act("forge_roll", held))
	hud.forge_take.connect(func(): _act("forge_take"))
	hud.forge_leave.connect(func(): _act("forge_leave"))
	hud.fps_toggled.connect(func(): set_fps_cap(30 if fps_cap == 60 else 60))
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
	_start()
	_resize_viewport()

func _start() -> void:
	sim = Sim.new()
	sim.setup(team_size, int(Time.get_unix_time_from_system()) & 0x7fffffff)
	view = View.new()
	view.low_fx = low_fx
	viewport.add_child(view)
	view.setup(sim)
	hud.sim = sim
	_accum = 0.0
	_result_shown = false

func _restart() -> void:
	if is_instance_valid(view):
		view.queue_free()
	if hud.result_panel != null:
		hud.result_panel.queue_free()
		hud.result_panel = null
	_start()

func _resize_viewport() -> void:
	# Render at physical pixel density so the 3D stays crisp under canvas_items stretching.
	# 3D renders at 80% of physical pixels (the HUD stays full resolution); fill rate is the main
	# GPU cost on phones and the difference is hard to see at this camera distance.
	var scale := get_global_transform_with_canvas().get_scale() * RENDER_SCALE
	var k := minf(1.0, MAX_3D_WIDTH / maxf(1.0, size.x * scale.x))
	viewport.size = Vector2i(maxi(64, int(size.x * scale.x * k)), maxi(64, int(size.y * scale.y * k)))
	if diag != null:
		diag.write("3D RES %dx%d (screen %dx%d logical, refresh %.0f Hz, fps cap %d)" % [viewport.size.x, viewport.size.y,
			int(size.x), int(size.y), DisplayServer.screen_get_refresh_rate(), fps_cap])

func _to_hud(p: Vector2) -> Vector2:
	var vs := Vector2(viewport.size)
	return p * (size / vs) if vs.x > 0 else p

func _act(action: String, arg: Variant = null) -> void:
	var ok: bool = sim.act(hud.player_id, action, arg)
	if ok and action == "forge_roll" and audio != null and audio.has_method("play"):
		audio.play("roll")

func _on_action(kind: String) -> void:
	match kind:
		"attack": _act("attack")
		"ability": _act("ability")
		"dodge": _act("dodge")
		"action": _act("interact")

func _process(delta: float) -> void:
	if sim == null:
		return
	diag.mark("input")
	var t_start := Time.get_ticks_usec()
	if not hud.pause_panel.visible or sim.ended:
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
		hud.show_result()

func _thermal_guard(delta: float) -> void:
	_guard_clock += delta
	if _guard_clock < 1.0:
		return
	_guard_clock = 0.0
	if fps_cap != 60 or hud.pause_panel.visible:
		_guard_low = 0
		return
	_guard_low = _guard_low + 1 if Engine.get_frames_per_second() < GUARD_FPS else 0
	if _guard_low >= GUARD_SECONDS:
		_guard_low = 0
		guard_tripped = true
		diag.write("THERMAL GUARD fps under %d for %ds -> 30 fps" % [GUARD_FPS, GUARD_SECONDS])
		set_fps_cap(30)
		hud.toast("Device running hot: 30 FPS mode on", Color("#f2d18d"))

func set_fps_cap(v: int) -> void:
	fps_cap = v
	Engine.max_fps = v
	if diag != null:
		diag.write("FPS CAP %d" % v)

func _exit_tree() -> void:
	Engine.max_fps = _prev_max_fps

func request_leave() -> void:
	# Android back button: open the pause panel rather than quitting a match outright.
	if hud.result_panel != null:
		exited.emit()
	else:
		hud.pause_panel.visible = true
		hud._center(hud.pause_panel)
