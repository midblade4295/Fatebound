extends SceneTree
# 0.31.160 (Kevin: "Check logs for moba mode and see if we can improve the performance of fps" -- his S21 Ultra: 14-20
# fps in a 5v5 at 6:00, sim 20-35 ms, view 12-16 ms, hud 7 ms, process 70-90 ms a frame): a 5v5 played by bots to
# FAST s (sim only), then the real game (sim + view + HUD) for FRAMES frames at a fixed 30 fps step, timed per part:
# the sim's steps, the view's sync, the HUD, and the whole process step (Performance TIME_PROCESS: those, plus the
# engine's own work -- the animation players, skeletons). CFG picks a configuration to compare:
#   base | noanim (every AnimationPlayer stopped) | nohud | nofog | nobush | noshadow (minions and monsters) | lod
#   (their meshes' lod_bias 0.25) | lite (both) | lodthr (the viewport's mesh_lod_threshold LODT, default 4 px) |
#   phys30 (physics at 30 Hz; the match sets that itself since 0.31.160)
# PHONE=1: the 3D viewport at the S21 Ultra's 1440x3200 while measuring (true primitive counts; slow under llvmpipe).
# Under llvmpipe "proc" is mostly the software renderer: compare the parts, not proc.
#   CFG=base FB_FORCE_HQ=1 DISPLAY=:98 godot --rendering-method mobile --resolution 420x933 --fixed-fps 30 --path godot -s res://tests/moba_bench.gd
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")

var mode
var phase := "boot"
var frames := 0
var samples := {"rag": [], "loose": [], "proc": [], "phys": [], "sim": [], "view": [], "hud": [], "anim": [], "units": [], "actors": [], "prims": [], "draws": [], "sprims": []}
var _done := {}
var cfg := "base"
var fast := 330.0
var nframes := 240

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")
	cfg = OS.get_environment("CFG") if OS.has_environment("CFG") else "base"
	fast = float(OS.get_environment("FAST")) if OS.has_environment("FAST") else 330.0
	nframes = int(OS.get_environment("FRAMES")) if OS.has_environment("FRAMES") else 240
	mode = Mode.new()
	mode.moba_hero = "rogue"
	mode.match_seed = 4401
	root.add_child(mode)

func _process(_delta: float) -> bool:
	frames += 1
	match phase:
		"boot":
			if mode.sim != null and mode._build_queue.is_empty() and frames > 30:
				var s = mode.sim
				s.by_id["you"].bot = true
				var t0 := Time.get_ticks_msec()
				while s.time < fast and not s.ended:
					s.step()
				s.drain_events()
				print("BENCH fast-forward to %.0f s: %d ms (units %d)" % [s.time, Time.get_ticks_msec() - t0, s.units.size()])
				phase = "settle"
				frames = 0
		"settle":
			if frames > 150:
				phase = "measure"
				frames = 0
				mode.view.prof_on = true
				mode.view.prof = {}
				mode.sim.profile = true
				mode.sim.prof = {}
				mode.hud.prof_on = true
				mode.hud.prof = {}
				if cfg == "nohud":
					mode.hud.visible = false
					mode.hud.process_mode = Node.PROCESS_MODE_DISABLED
				if OS.has_environment("PHONE"):
					mode.viewport.size = Vector2i(1440, 3200)      # the S21 Ultra's 3D at 100 % (for the primitive counts; slow here)
				if cfg == "phys30":
					Engine.physics_ticks_per_second = 30
				if cfg == "lodthr":
					mode.viewport.mesh_lod_threshold = float(OS.get_environment("LODT")) if OS.has_environment("LODT") else 4.0
					print("BENCH mesh_lod_threshold ", mode.viewport.mesh_lod_threshold)
				if cfg in ["nofog", "nofogbush"]:
					mode.view.fog_on = false
				if cfg in ["nobush", "nofogbush"]:
					var nb := 0
					for c in mode.view.get_children():
						if c is MultiMeshInstance3D and str(c.name).begins_with("Brush_"):
							nb += (c as MultiMeshInstance3D).multimesh.instance_count
							(c as Node3D).visible = false
					print("BENCH bushes hidden: ", nb)
		"measure":
			if cfg in ["noshadow", "lod", "lite"]:
				for id in mode.view.actors:
					var a2: Dictionary = mode.view.actors[id]
					var b = a2.get("body")
					if b == null or not is_instance_valid(b) or _done.has(b.get_instance_id()):
						continue
					_done[b.get_instance_id()] = true
					var minion: bool = bool(mode.sim.by_id.get(id, {}).get("minion", false)) or mode.sim.by_id.get(id, {}).has("mon")
					for mi in (b as Node).find_children("*", "MeshInstance3D", true, false):
						if cfg in ["noshadow", "lite"] and minion:
							(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
						if cfg in ["lod", "lite"]:
							(mi as MeshInstance3D).lod_bias = 0.25
			if cfg == "noanim":
				for id in mode.view.actors:
					var a: Dictionary = mode.view.actors[id]
					if is_instance_valid(a.get("player")):
						(a.player as AnimationPlayer).active = false
			var t: Dictionary = mode.diag._times
			samples.proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			samples.phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
			samples.rag.append(float(mode.view._ragdolls.size()))
			samples.loose.append(float(mode.view._debris.size()))
			samples.sim.append(_last(t, "sim"))
			samples.view.append(_last(t, "view"))
			samples.hud.append(_last(t, "hud"))
			samples.anim.append(float(mode.view.anim_active))
			samples.units.append(float(mode.sim.units.size()))
			samples.actors.append(float(mode.view.actors.size()))
			var vp: RID = mode.viewport.get_viewport_rid()
			samples.prims.append(float(RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)))
			samples.draws.append(float(RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)))
			samples.sprims.append(float(RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)))
			mode.diag._times.clear()
			if frames >= nframes:
				var line := "BENCH %s:" % cfg
				for k in ["rag", "loose", "proc", "phys", "sim", "view", "hud", "anim", "units", "actors", "prims", "sprims", "draws"]:
					var arr: Array = (samples[k] as Array).duplicate()
					arr.sort()
					var sum := 0.0
					for x in arr:
						sum += float(x)
					var n := arr.size()
					line += " %s=%.2f(med %.2f p90 %.2f)" % [k, sum / maxf(1.0, n), float(arr[n / 2]), float(arr[int(n * 0.9)])]
				print(line)
				for pr in [["view", mode.view.prof], ["sim", mode.sim.prof], ["hud", mode.hud.prof]]:
					var pd: Dictionary = pr[1]
					var keys: Array = pd.keys()
					keys.sort_custom(func(x, y): return int(pd[x]) > int(pd[y]))
					var t2 := "BENCH %s parts:" % pr[0]
					for k2 in keys:
						t2 += " %s=%.3f" % [k2, float(pd[k2]) / 1000.0 / float(nframes)]
					print(t2)
				quit(0)
				return true
	return false

func _last(t: Dictionary, k: String) -> float:
	var v: Array = t.get(k, [0, 0, 0])
	return float(v[0]) / 1000.0
