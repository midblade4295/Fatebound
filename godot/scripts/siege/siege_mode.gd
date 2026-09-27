extends Control
# Offline Siege match: you plus bots. Owns the simulation, steps it at a fixed rate, and feeds the
# 3D view and HUD. Emits `exited` when the player leaves.
const Sim = preload("res://scripts/siege/siege_sim.gd")
const View = preload("res://scripts/siege/siege_view.gd")
const Hud = preload("res://scripts/siege/siege_hud.gd")

signal exited

var team_size := 6
const RENDER_SCALE := 0.8
var low_fx := false
var audio: Node = null

var sim
var view
var hud
var viewport: SubViewport
var _accum := 0.0
var _result_shown := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_2X
	# The imports already generate LODs; a higher threshold lets small, distant heroes use them.
	viewport.mesh_lod_threshold = 4.0
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
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
	add_child(hud)
	hud.leave_requested.connect(func(): exited.emit())
	hud.replay_requested.connect(_restart)
	hud.forge_roll.connect(func(held): _act("forge_roll", held))
	hud.forge_take.connect(func(): _act("forge_take"))
	hud.forge_leave.connect(func(): _act("forge_leave"))
	hud.action_pressed.connect(_on_action)
	hud.project = func(world: Vector3) -> Vector2: return _to_hud(view.screen_point(world))
	hud.on_screen = func(world: Vector3) -> bool: return view.is_on_screen(world)
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
	viewport.size = Vector2i(maxi(64, int(size.x * scale.x)), maxi(64, int(size.y * scale.y)))

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
	if not hud.pause_panel.visible or sim.ended:
		sim.set_move(hud.player_id, hud.move_vector())
		if hud.attack_held():
			var me: Dictionary = sim.by_id[hud.player_id]
			if sim.can_act(me) and not me.carrying:
				sim.act(hud.player_id, "attack")
		_accum += minf(delta, 0.1)
		while _accum >= Sim.TICK:
			_accum -= Sim.TICK
			sim.step(Sim.TICK)
		for e in sim.drain_events():
			view.on_event(e)
			hud.on_event(e)
	view.sync(delta)
	if sim.ended and not _result_shown:
		_result_shown = true
		hud.show_result()

func request_leave() -> void:
	# Android back button: open the pause panel rather than quitting a match outright.
	if hud.result_panel != null:
		exited.emit()
	else:
		hud.pause_panel.visible = true
		hud._center(hud.pause_panel)
