extends SceneTree
# 0.31.207: what makes a match frame long -- a 5v5 of bots (you one of them) for SECS seconds, every frame timed; a
# frame over SLOW ms is listed with what was new in it: spell_fx particle materials (their shaders) and sprite
# materials, the engine's pipeline compiles, actors. Ends with the count of long frames and the worst.
#   Xvfb :97 & DISPLAY=:97 godot --rendering-method mobile --resolution 420x933 --path godot -s res://tools/hitch_bench.gd
# SECS (default 90), SLOW (ms, default 40), HERO (default mage), SEED (default 4402), WARM (1: the match's warm-up on).
const Mode = preload("res://scripts/siege/siege_mode.gd")
const SpellFx = preload("res://scripts/siege/spell_fx.gd")
var mode
var frames := 0
var secs := 90.0
var slow := 40.0
var t_last := 0
var started := -1.0
var long := []
var worst := 0.0
var n_frames := 0
var pms0 := 0
var mats0 := 0
var pipes0 := 0
var _recent: Array = []
var nodes0 := 0
var actors0 := 0
var pipe_frames := 0
var pipe_new := 0
var _ev_prev: Array = []

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")
	if OS.has_environment("SECS"):
		secs = float(OS.get_environment("SECS"))
	if OS.has_environment("SLOW"):
		slow = float(OS.get_environment("SLOW"))
	if OS.has_environment("WARM"):
		OS.set_environment("FB_FORCE_WARMUP", "1")
	mode = Mode.new()
	mode.moba_hero = OS.get_environment("HERO") if OS.has_environment("HERO") else "mage"
	mode.match_seed = int(OS.get_environment("SEED")) if OS.has_environment("SEED") else 4402
	mode.warm_max = 120.0                           # (software rendering here: the warm-up's frames are slow)
	root.add_child(mode)

static func pipes() -> int:
	var c := 0
	for k in [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]:
		c += RenderingServer.get_rendering_info(k)
	return c

var _by0 := []
func pipes_by() -> Array:
	# the new compiles since the last call, by kind: canvas, mesh, surface, draw, specialization
	var out := []
	var i := 0
	for k in [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]:
		var c := RenderingServer.get_rendering_info(k)
		out.append(c - (int(_by0[i]) if i < _by0.size() else 0))
		i += 1
	_by0 = []
	for k2 in [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]:
		_by0.append(RenderingServer.get_rendering_info(k2))
	return out

func _process(_d: float) -> bool:
	frames += 1
	var now := Time.get_ticks_usec()
	var dt := (now - t_last) / 1000.0 if t_last > 0 else 0.0
	t_last = now
	if mode.sim == null or not mode.warmed():
		return false
	var s = mode.sim
	if started < 0.0:
		started = now / 1e6
		var me: Dictionary = s.by_id["you"]
		me.bot = true                                   # (a bot plays you too)
		pms0 = SpellFx._pms.size()
		mats0 = SpellFx._mats.size()
		pipes0 = pipes()
		mode.view.ev_log = []
		pipes_by()
		print("BENCH start t=%.1f pms=%d mats=%d pipes=%d  warm: %d looks shown, %d bodies pooled" % [s.time, pms0, mats0, pipes0,
			int(mode.view.fxs.warm_shown), mode.view.pool_size()])
		return false
	n_frames += 1
	var pm := SpellFx._pms.size()
	var mt := SpellFx._mats.size()
	var pp := pipes()
	_recent.append(dt)
	if _recent.size() > 31:
		_recent.pop_front()
	var srt := _recent.duplicate()
	srt.sort()
	var med: float = srt[srt.size() / 2]
	var spike := dt > maxf(slow, med * 1.7) and n_frames > 10
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var actors: int = mode.view.actors.size()
	var news := pm > pms0 or mt > mats0 or pp > pipes0
	var by := pipes_by()
	if spike:
		long.append(dt)
		worst = maxf(worst, dt / med)
	if spike or news:
		print("%s %.0f ms (median %.0f)  t=%.1f  new pms=%d mats=%d pipes=%d %s  fx=%d live  nodes %+d  actors %+d (%d)  units %d  pool %d  cam %s  events %s" % ["LONG" if spike else "new ", dt, med, s.time,
			pm - pms0, mt - mats0, pp - pipes0, str(by), mode.view.fxs._live.size(), nodes - nodes0, actors - actors0, actors, s.units.size(), mode.view.pool_size(), str(Vector2(mode.view.camera.global_position.x, mode.view.camera.global_position.z).round()),
			str(_ev_prev + (mode.view.ev_log as Array))])
	if pp > pipes0:
		pipe_frames += 1
		pipe_new += pp - pipes0
	_ev_prev = (mode.view.ev_log as Array).duplicate()
	mode.view.ev_log = []
	pms0 = pm
	mats0 = mt
	pipes0 = pp
	nodes0 = nodes
	actors0 = actors
	if now / 1e6 - started > secs:
		print("BENCH %d frames, %d spikes (over 1.7x the median), worst %.1fx; spell_fx materials: %d particle, %d sprite; %d frames with new pipelines (%d); bodies %d built, %d from the pool" % [n_frames, long.size(), worst,
			SpellFx._pms.size(), SpellFx._mats.size(), pipe_frames, pipe_new, mode.view.pool_built, mode.view.pool_reused])
		quit(0)
	return false
